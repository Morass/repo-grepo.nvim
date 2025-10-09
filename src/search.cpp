#include <algorithm>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <regex>
#include <string>
#include <vector>

namespace fs = std::filesystem;

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

bool should_skip_path(const std::string& path, const std::vector<std::regex>& banned_regexes) {
    for (const auto& regex : banned_regexes) {
        if (std::regex_search(path, regex)) {
            return true;
        }
    }
    return false;
}

bool should_include_file(const std::string& path, const std::vector<std::regex>& include_regexes) {
    if (include_regexes.empty()) {
        return true;
    }

    // Extract just the filename for matching
    const size_t last_slash = path.find_last_of("/\\");
    const std::string filename = (last_slash != std::string::npos) ? path.substr(last_slash + 1) : path;

    for (const auto& regex : include_regexes) {
        if (std::regex_match(filename, regex)) {
            return true;
        }
    }
    return false;
}

std::vector<std::regex> parse_regex_list(const std::string& input, bool use_glob = true) {
    std::vector<std::regex> result;
    if (input.empty()) {
        return result;
    }

    std::string current;
    for (char c : input) {
        if (c == ',') {
            if (!current.empty()) {
                try {
                    std::string pattern = use_glob ? glob_to_regex(current) : current;
                    result.push_back(std::regex(pattern, std::regex::ECMAScript | std::regex::optimize));
                } catch (const std::regex_error&) {
                    // Skip invalid regex
                }
                current.clear();
            }
        } else {
            current += c;
        }
    }
    if (!current.empty()) {
        try {
            std::string pattern = use_glob ? glob_to_regex(current) : current;
            result.push_back(std::regex(pattern, std::regex::ECMAScript | std::regex::optimize));
        } catch (const std::regex_error&) {
            // Skip invalid regex
        }
    }
    return result;
}

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

    auto include_regexes = parse_regex_list(include_str, true);  // Use glob matching
    auto banned_regexes = parse_regex_list(banned_str, true);   // Use glob matching

    std::vector<FileMatch> matches;

    try {
        fs::recursive_directory_iterator iter(root_path, fs::directory_options::skip_permission_denied);
        fs::recursive_directory_iterator end;

        for (; iter != end; ++iter) {
            const auto& entry = *iter;
            std::string relative_path = fs::relative(entry.path(), root_path).string();

            // Skip banned directories early (don't recurse into them)
            if (entry.is_directory()) {
                if (should_skip_path(relative_path, banned_regexes)) {
                    iter.disable_recursion_pending();
                }
                continue;
            }

            if (!entry.is_regular_file()) {
                continue;
            }

            // Check if path should be skipped
            if (should_skip_path(relative_path, banned_regexes)) {
                continue;
            }

            // Check if file should be included
            if (!should_include_file(relative_path, include_regexes)) {
                continue;
            }

            // Skip binary files by checking for null bytes in first 512 bytes
            std::ifstream file(entry.path(), std::ios::binary);
            if (!file.is_open()) {
                continue;
            }

            constexpr size_t BUFFER_SIZE = 512;
            char buffer[BUFFER_SIZE];
            file.read(buffer, BUFFER_SIZE);
            const std::streamsize bytes_read = file.gcount();

            bool is_binary = false;
            for (std::streamsize i = 0; i < bytes_read; ++i) {
                if (buffer[i] == '\0') {
                    is_binary = true;
                    break;
                }
            }

            if (is_binary) {
                continue;
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
                matches.push_back({relative_path, static_cast<int>(match_count)});
            }
        }
    } catch (const fs::filesystem_error& e) {
        std::cerr << "ERROR: Filesystem error: " << e.what() << std::endl;
        return;
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
