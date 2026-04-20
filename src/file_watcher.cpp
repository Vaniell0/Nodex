#include "nodex/file_watcher.hpp"

#include <unordered_set>

namespace fs = std::filesystem;

namespace nodex {

FileWatcher::FileWatcher(Config config)
    : config_(std::move(config)) {
    // Initialize with current file states
    for (const auto& file : ScanFiles()) {
        try {
            mtimes_[file] = fs::last_write_time(file);
        } catch (...) {}
    }
}

FileWatcher::~FileWatcher() {
    Stop();
}

void FileWatcher::OnChange(ChangeCallback cb) {
    callback_ = std::move(cb);
}

void FileWatcher::Start() {
    running_ = true;
    watch_thread_ = std::thread([this]() {
        while (running_) {
            std::this_thread::sleep_for(config_.interval);
            if (!running_) break;

            auto changed = DetectChanges();
            if (!changed.empty() && callback_) {
                callback_(changed);
            }
        }
    });
}

void FileWatcher::Stop() {
    running_ = false;
    if (watch_thread_.joinable()) {
        watch_thread_.join();
    }
}

std::vector<std::string> FileWatcher::ScanFiles() const {
    std::vector<std::string> files;
    for (const auto& dir : config_.directories) {
        if (!fs::exists(dir)) continue;
        try {
            for (auto& entry : fs::recursive_directory_iterator(dir)) {
                if (!entry.is_regular_file()) continue;
                auto ext = entry.path().extension().string();
                for (const auto& wanted : config_.extensions) {
                    if (ext == wanted) {
                        files.push_back(entry.path().string());
                        break;
                    }
                }
            }
        } catch (...) {}
    }
    return files;
}

std::vector<std::string> FileWatcher::DetectChanges() {
    std::vector<std::string> changed;
    auto current_files = ScanFiles();

    std::unordered_set<std::string> current_set(current_files.begin(), current_files.end());

    // Detect new/modified
    for (const auto& file : current_files) {
        try {
            auto mtime = fs::last_write_time(file);
            auto it = mtimes_.find(file);
            if (it == mtimes_.end() || it->second != mtime) {
                changed.push_back(file);
                mtimes_[file] = mtime;
            }
        } catch (...) {}
    }

    // Detect deletions — O(n) via unordered_set
    std::vector<std::string> deleted;
    for (const auto& [path, _] : mtimes_) {
        if (!current_set.contains(path))
            deleted.push_back(path);
    }
    for (const auto& d : deleted) {
        mtimes_.erase(d);
        changed.push_back(d);
    }

    return changed;
}

} // namespace nodex
