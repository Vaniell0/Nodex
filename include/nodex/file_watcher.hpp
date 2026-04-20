#pragma once

#include <atomic>
#include <chrono>
#include <filesystem>
#include <functional>
#include <map>
#include <string>
#include <thread>
#include <vector>

namespace nodex {

class FileWatcher {
public:
    struct Config {
        std::vector<std::string> directories;
        std::vector<std::string> extensions = {".html", ".json", ".css", ".js"};
        std::chrono::milliseconds interval{500};
    };

    explicit FileWatcher(Config config);
    ~FileWatcher();

    using ChangeCallback = std::function<void(const std::vector<std::string>&)>;
    void OnChange(ChangeCallback cb);

    void Start();
    void Stop();
    bool Running() const { return running_.load(); }

private:
    Config config_;
    ChangeCallback callback_;
    std::atomic<bool> running_{false};
    std::thread watch_thread_;
    std::map<std::string, std::filesystem::file_time_type> mtimes_;

    std::vector<std::string> ScanFiles() const;
    std::vector<std::string> DetectChanges();
};

} // namespace nodex
