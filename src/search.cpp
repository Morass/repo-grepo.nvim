#include <algorithm>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <regex>
#include <string>
#include <vector>
#include <thread>
#include <mutex>
#include <queue>
#include <condition_variable>
#include <atomic>

namespace fs = std::filesystem;

constexpr int THREAD_POOL_SIZE = 20;

struct FileMatch {
    std::string path;
    int count;
};

struct LineMatch {
    int line_number;
    std::string content;
};

// Convert glob pattern to regex pattern
std::string glob_to_regex(const std::string& glob) {
    std::string regex;
    regex.reserve(glob.size() * 2);  // Pre-allocate to avoid reallocations

    for (char c : glob) {
        switch (c) {
            case '*':
                regex += ".*";
                break;
            case '?':
                regex += ".";
                break;
            case '.':
                regex += "\\.";
                break;
            case '+':
            case '(':
            case ')':
            case '[':
            case ']':
            case '{':
            case '}':
            case '^':
            case '$':
            case '|':
            case '\\':
                regex += '\\';
                regex += c;
                break;
            default:
                regex += c;
        }
    }
    return regex;
}

bool should_skip_path(const std::string& path, const std::regex& banned_regex) {
    return std::regex_search(path, banned_regex);
}

bool should_include_file(const std::string& path, const std::regex* include_regex) {
    if (!include_regex) {
        return true;
    }

    // Extract just the filename for matching
    const size_t last_slash = path.find_last_of("/\\");
    const std::string filename = (last_slash != std::string::npos) ? path.substr(last_slash + 1) : path;

    return std::regex_match(filename, *include_regex);
}

// Build a single combined regex from comma-separated patterns using OR (|)
std::regex* build_combined_regex(const std::string& input, bool use_glob = true) {
    if (input.empty()) {
        return nullptr;
    }

    std::string combined_pattern;
    std::string current;

    for (char c : input) {
        if (c == ',') {
            if (!current.empty()) {
                if (!combined_pattern.empty()) {
                    combined_pattern += "|";
                }
                std::string pattern = use_glob ? glob_to_regex(current) : current;
                combined_pattern += "(" + pattern + ")";
                current.clear();
            }
        } else {
            current += c;
        }
    }

    if (!current.empty()) {
        if (!combined_pattern.empty()) {
            combined_pattern += "|";
        }
        std::string pattern = use_glob ? glob_to_regex(current) : current;
        combined_pattern += "(" + pattern + ")";
    }

    try {
        return new std::regex(combined_pattern, std::regex::ECMAScript | std::regex::optimize);
    } catch (const std::regex_error&) {
        return nullptr;
    }
}

// Thread-safe queue for work distribution
template<typename T>
class ThreadSafeQueue {
private:
    std::queue<T> queue_;
    mutable std::mutex mutex_;
    std::condition_variable cv_;
    std::atomic<bool> done_{false};

public:
    void push(T item) {
        {
            std::lock_guard<std::mutex> lock(mutex_);
            queue_.push(std::move(item));
        }
        cv_.notify_one();
    }

    bool pop(T& item) {
        std::unique_lock<std::mutex> lock(mutex_);
        cv_.wait(lock, [this] { return !queue_.empty() || done_; });

        if (queue_.empty()) {
            return false;
        }

        item = std::move(queue_.front());
        queue_.pop();
        return true;
    }

    void set_done() {
        done_ = true;
        cv_.notify_all();
    }

    size_t size() const {
        std::lock_guard<std::mutex> lock(mutex_);
        return queue_.size();
    }
};

void scan_files(const std::string& root_path,
                const std::string& pattern_str,
                const std::string& include_str,
                const std::string& banned_str) {

    std::regex pattern;
    try {
        pattern = std::regex(pattern_str, std::regex::ECMAScript | std::regex::optimize);
    } catch (const std::regex_error& e) {
        std::cerr << "ERROR: Invalid regex pattern: " << pattern_str << std::endl;
        return;
    }

    // Build combined regexes for better performance (one check instead of loop)
    std::regex* include_regex = build_combined_regex(include_str, true);
    std::regex* banned_regex = build_combined_regex(banned_str, true);

    // Phase 1: PARALLEL directory discovery
    std::vector<std::pair<fs::path, std::string>> files_to_process;
    std::mutex files_mutex;

    ThreadSafeQueue<fs::path> dirs_to_explore;
    std::atomic<int> active_explorers{0};

    dirs_to_explore.push(fs::path(root_path));

    // Start explorer threads
    std::vector<std::thread> explorer_threads;
    for (int i = 0; i < THREAD_POOL_SIZE; ++i) {
        explorer_threads.emplace_back([&]() {
            // Thread-local batch to reduce lock contention
            std::vector<std::pair<fs::path, std::string>> local_files;
            local_files.reserve(100);

            fs::path dir;
            while (dirs_to_explore.pop(dir)) {
                active_explorers++;

                try {
                    std::error_code ec;
                    for (const auto& entry : fs::directory_iterator(dir,
                            fs::directory_options::skip_permission_denied, ec)) {

                        if (ec) continue;

                        std::string relative_path = fs::relative(entry.path(), root_path, ec).string();
                        if (ec) continue;

                        // Check if banned
                        if (banned_regex && should_skip_path(relative_path, *banned_regex)) {
                            continue;
                        }

                        if (entry.is_directory(ec) && !ec) {
                            dirs_to_explore.push(entry.path());
                        } else if (entry.is_regular_file(ec) && !ec) {
                            if (should_include_file(relative_path, include_regex)) {
                                local_files.push_back({entry.path(), std::move(relative_path)});
                            }
                        }
                    }
                } catch (const fs::filesystem_error&) {
                    // Skip directories with errors
                }

                active_explorers--;
            }

            // Merge thread-local results into shared vector
            if (!local_files.empty()) {
                std::lock_guard<std::mutex> lock(files_mutex);
                files_to_process.insert(files_to_process.end(),
                                      std::make_move_iterator(local_files.begin()),
                                      std::make_move_iterator(local_files.end()));
            }
        });
    }

    // Wait until all directories explored
    while (dirs_to_explore.size() > 0 || active_explorers > 0) {
        std::this_thread::sleep_for(std::chrono::milliseconds(1));
    }

    dirs_to_explore.set_done();
    for (auto& t : explorer_threads) {
        t.join();
    }

    // Phase 2: Parallel file processing
    std::vector<FileMatch> matches;
    std::mutex matches_mutex;
    std::atomic<size_t> next_file_index{0};

    auto process_file = [&](const fs::path& file_path, const std::string& relative_path) {
        // Skip binary files
        std::ifstream file(file_path, std::ios::binary);
        if (!file.is_open()) {
            return;
        }

        constexpr size_t BUFFER_SIZE = 512;
        char buffer[BUFFER_SIZE];
        file.read(buffer, BUFFER_SIZE);
        const std::streamsize bytes_read = file.gcount();

        for (std::streamsize i = 0; i < bytes_read; ++i) {
            if (buffer[i] == '\0') {
                return; // Binary file
            }
        }

        // Reset to beginning for actual search
        file.seekg(0);

        size_t match_count = 0;
        std::string line;
        while (std::getline(file, line)) {
            if (std::regex_search(line, pattern)) {
                ++match_count;
            }
        }

        if (match_count > 0) {
            std::lock_guard<std::mutex> lock(matches_mutex);
            matches.push_back({relative_path, static_cast<int>(match_count)});
        }
    };

    auto file_worker = [&]() {
        while (true) {
            size_t index = next_file_index.fetch_add(1);
            if (index >= files_to_process.size()) {
                break;
            }
            const auto& file_info = files_to_process[index];
            process_file(file_info.first, file_info.second);
        }
    };

    // Start file processing threads
    std::vector<std::thread> file_threads;
    for (int i = 0; i < THREAD_POOL_SIZE; ++i) {
        file_threads.emplace_back(file_worker);
    }

    for (auto& t : file_threads) {
        t.join();
    }

    // Sort by count (descending) then by path (ascending)
    std::sort(matches.begin(), matches.end(), [](const FileMatch& a, const FileMatch& b) {
        if (a.count != b.count) {
            return a.count > b.count;
        }
        return a.path < b.path;
    });

    // Output results
    for (const auto& match : matches) {
        std::cout << match.path << "|" << match.count << std::endl;
    }

    // Cleanup
    delete include_regex;
    delete banned_regex;
}

void scan_file_lines(const std::string& file_path, const std::string& pattern_str) {
    std::regex pattern;
    try {
        pattern = std::regex(pattern_str, std::regex::ECMAScript | std::regex::optimize);
    } catch (const std::regex_error&) {
        std::cerr << "ERROR: Invalid regex pattern: " << pattern_str << std::endl;
        return;
    }

    std::ifstream file(file_path);
    if (!file.is_open()) {
        std::cerr << "ERROR: Cannot open file: " << file_path << std::endl;
        return;
    }

    std::string line;
    size_t line_number = 1;
    while (std::getline(file, line)) {
        if (std::regex_search(line, pattern)) {
            // Replace pipe characters to avoid conflicts with delimiter
            for (char& c : line) {
                if (c == '|') {
                    c = ' ';
                }
            }
            std::cout << line_number << "|" << line << std::endl;
        }
        ++line_number;
    }
}

int main(int argc, char* argv[]) {
    if (argc < 2) {
        std::cerr << "Usage: " << argv[0] << " <mode> <args...>\n"
                  << "Modes:\n"
                  << "  files <root_path> <pattern> <include_regexes> <banned_regexes>\n"
                  << "  lines <file_path> <pattern>\n";
        return 1;
    }

    const std::string mode = argv[1];

    if (mode == "files") {
        if (argc != 6) {
            std::cerr << "ERROR: files mode requires 4 arguments\n";
            return 1;
        }
        scan_files(argv[2], argv[3], argv[4], argv[5]);
    } else if (mode == "lines") {
        if (argc != 4) {
            std::cerr << "ERROR: lines mode requires 2 arguments\n";
            return 1;
        }
        scan_file_lines(argv[2], argv[3]);
    } else {
        std::cerr << "ERROR: Unknown mode: " << mode << '\n';
        return 1;
    }

    return 0;
}
