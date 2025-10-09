#include <iostream>
#include <fstream>
#include <string>
#include <vector>
#include <regex>
#include <algorithm>
#include <filesystem>
#include <map>
#include <cstring>

namespace fs = std::filesystem;

struct FileMatch {
    std::string path;
    int count;
};

struct LineMatch {
    int line_number;
    std::string content;
};

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
    for (const auto& regex : include_regexes) {
        if (std::regex_search(path, regex)) {
            return true;
        }
    }
    return false;
}

std::vector<std::regex> parse_regex_list(const std::string& input) {
    std::vector<std::regex> result;
    if (input.empty()) {
        return result;
    }

    std::string current;
    for (char c : input) {
        if (c == ',') {
            if (!current.empty()) {
                try {
                    result.push_back(std::regex(current, std::regex::ECMAScript | std::regex::optimize));
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
            result.push_back(std::regex(current, std::regex::ECMAScript | std::regex::optimize));
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

    auto include_regexes = parse_regex_list(include_str);
    auto banned_regexes = parse_regex_list(banned_str);

    std::vector<FileMatch> matches;

    try {
        for (const auto& entry : fs::recursive_directory_iterator(
                root_path,
                fs::directory_options::skip_permission_denied)) {

            if (!entry.is_regular_file()) {
                continue;
            }

            std::string relative_path = fs::relative(entry.path(), root_path).string();

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

            char buffer[512];
            file.read(buffer, sizeof(buffer));
            std::streamsize bytes_read = file.gcount();
            bool is_binary = false;
            for (std::streamsize i = 0; i < bytes_read; ++i) {
                if (buffer[i] == '\0') {
                    is_binary = true;
                    break;
                }
            }

            if (is_binary) {
                file.close();
                continue;
            }

            // Reset to beginning for actual search
            file.seekg(0);

            int match_count = 0;
            std::string line;
            while (std::getline(file, line)) {
                if (std::regex_search(line, pattern)) {
                    match_count++;
                }
            }
            file.close();

            if (match_count > 0) {
                matches.push_back({relative_path, match_count});
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
    } catch (const std::regex_error& e) {
        std::cerr << "ERROR: Invalid regex pattern: " << pattern_str << std::endl;
        return;
    }

    std::ifstream file(file_path);
    if (!file.is_open()) {
        std::cerr << "ERROR: Cannot open file: " << file_path << std::endl;
        return;
    }

    std::string line;
    int line_number = 1;
    while (std::getline(file, line)) {
        if (std::regex_search(line, pattern)) {
            // Replace pipe characters to avoid conflicts with delimiter
            std::string safe_line = line;
            for (char& c : safe_line) {
                if (c == '|') {
                    c = ' ';
                }
            }
            std::cout << line_number << "|" << safe_line << std::endl;
        }
        line_number++;
    }
    file.close();
}

int main(int argc, char* argv[]) {
    if (argc < 2) {
        std::cerr << "Usage: " << argv[0] << " <mode> <args...>" << std::endl;
        std::cerr << "Modes:" << std::endl;
        std::cerr << "  files <root_path> <pattern> <include_regexes> <banned_regexes>" << std::endl;
        std::cerr << "  lines <file_path> <pattern>" << std::endl;
        return 1;
    }

    std::string mode = argv[1];

    if (mode == "files") {
        if (argc != 6) {
            std::cerr << "ERROR: files mode requires 4 arguments" << std::endl;
            return 1;
        }
        scan_files(argv[2], argv[3], argv[4], argv[5]);
    } else if (mode == "lines") {
        if (argc != 4) {
            std::cerr << "ERROR: lines mode requires 2 arguments" << std::endl;
            return 1;
        }
        scan_file_lines(argv[2], argv[3]);
    } else {
        std::cerr << "ERROR: Unknown mode: " << mode << std::endl;
        return 1;
    }

    return 0;
}
