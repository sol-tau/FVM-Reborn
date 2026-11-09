/// 

// FvmNativeSupport.dll（extensions/WindowsNative）只拷到 Windows 目标。
// 其他平台（macOS 等）没有这个 dll，下面的方法改用 GameMaker 自带函数实现同样的语义，
// 返回码沿用 native 侧约定：0 = 成功，负数 = 自定义错误（见 FvmNativeSupport/Typedef.h）。
#macro kHasWindowsNative (os_type == os_windows)
#macro kNativeErrJsonParseFailed -2
#macro kNativeErrCancelled -3
#macro kNativeErrUnknownFailure -5
#macro kNativeErrExtractFailed -12

function NativeUtil() constructor {

    
    /// @param {String} _path 
    /// @returns {String}
    static get_path_in_local_appdata = function(_path) {
        if (!kHasWindowsNative) {
            return self.to_save_area_path(_path)
        }
        var _user_profile = environment_get_variable("LOCALAPPDATA")
        return self.transfer_path_to_windows(_user_profile + _path)
    }

    /// @param {String} _rel GML 沙盒相对路径
    /// @returns {String} native 可用的绝对路径
    static to_native_absolute = function(_rel) {
        if (!kHasWindowsNative) {
            _rel = self.to_posix_path(_rel)
            if (string_starts_with(_rel, "/")) {
                return _rel
            }
            return self.save_area_root() + _rel
        }
        _rel = string_replace_all(string(_rel), "/", "\\")
        while (string_starts_with(_rel, "\\")) {
            _rel = string_delete(_rel, 1, 1)
        }
        if (string_pos(":", _rel) > 0) {
            return self.transfer_path_to_windows(_rel)
        }
        return self.get_path_in_local_appdata("\\FVM_Reborn\\" + _rel)
    }

    /// @param {String} _path 
    /// @returns {String}
    static transfer_path_to_windows = function(_path) {
        return string_replace(_path, "/", "\\")
    }

    /// @param {Real} _code 
    /// @param {String} _msg 
    static show_error = function(_code, _msg) {
        show_message_async(_msg + "code: " + string(_code))
    }

    // ── 以下方法在 Windows 上原样转发给 native_*，其他平台用 GameMaker 自带函数 ──

    /// @param {String} _path
    /// @returns {Real} 1 = 存在，0 = 不存在
    static folder_exists = function(_path) {
        if (kHasWindowsNative) {
            return native_folder_exists(_path)
        }
        return directory_exists(self.to_posix_path(_path)) ? 1 : 0
    }

    /// @param {String} _path
    /// @returns {Real} 0 = 成功
    static delete_folder = function(_path) {
        if (kHasWindowsNative) {
            return native_delete_folder(_path)
        }
        var _dir = self.to_posix_path(_path)
        directory_destroy(_dir)
        return directory_exists(_dir) ? kNativeErrUnknownFailure : 0
    }

    /// @param {String} _path
    /// @returns {Real} 0 = 成功
    static open_folder = function(_path) {
        if (kHasWindowsNative) {
            return native_open_folder(_path)
        }
        var _dir = self.to_posix_path(_path)
        if (!directory_exists(_dir)) {
            return kNativeErrUnknownFailure
        }
        url_open(self.path_to_file_url(_dir))
        return 0
    }

    /// @param {String} _zip_path 压缩文件的完整路径
    /// @param {String} _dest 解压目标文件夹的完整路径
    /// @returns {Real} 0 = 成功
    static unzip_map_file = function(_zip_path, _dest) {
        if (kHasWindowsNative) {
            return native_unzip_map_file(_zip_path, _dest)
        }
        // zip_unzip 只认 zip；Windows 版用 7z.dll，还能解 7z / rar
        var _count = zip_unzip(self.to_posix_path(_zip_path), self.to_posix_path(_dest) + "/")
        return _count > 0 ? 0 : kNativeErrExtractFailed
    }

    /// @description 让玩家选一个位置，把存档目录下所有 .json 打包成一个备份文件。
    /// @param {String} _saves_dir
    /// @returns {Real} 0 = 成功，kNativeErrCancelled = 玩家取消
    static start_backup = function(_saves_dir) {
        if (kHasWindowsNative) {
            return native_start_backup(_saves_dir)
        }
        var _target = get_save_filename_ext("JSON Files (*.json)|*.json", "backup.json", "", "导出存档备份")
        if (_target == "") {
            return kNativeErrCancelled
        }
        return self.write_backup_file(self.to_posix_path(_saves_dir), _target)
    }

    /// @description 让玩家选一个备份文件，把里面的存档写回存档目录。
    /// @param {String} _saves_dir
    /// @param {String} _default_backup_dir 文件对话框的初始目录
    /// @returns {Real} 0 = 成功，kNativeErrCancelled = 玩家取消
    static restore_backup = function(_saves_dir, _default_backup_dir) {
        if (kHasWindowsNative) {
            return native_restore_backup(_saves_dir, _default_backup_dir)
        }
        var _dir = self.to_posix_path(_default_backup_dir)
        if (!directory_exists(_dir)) {
            _dir = ""
        }
        var _source = get_open_filename_ext("JSON Files (*.json)|*.json", "", _dir, "选择存档备份")
        if (_source == "") {
            return kNativeErrCancelled
        }
        return self.read_backup_file(self.to_posix_path(_saves_dir), _source)
    }

    // ── 非 Windows 平台的内部实现 ──

    /// @description 备份格式与 native StartBackupWithTargetFile 相同：
    ///              {"files": [{"name": "save0.json", "content": "<文件原文>"}, ...]}，两个平台的备份可以互相恢复。
    /// @param {String} _saves_dir
    /// @param {String} _target_file
    /// @returns {Real}
    static write_backup_file = function(_saves_dir, _target_file) {
        if (!string_ends_with(_saves_dir, "/")) {
            _saves_dir += "/"
        }
        if (!directory_exists(_saves_dir)) {
            directory_create(_saves_dir)
        }
        var _names = []
        var _name = file_find_first(_saves_dir + "*.json", 0)
        while (_name != "") {
            array_push(_names, _name)
            _name = file_find_next()
        }
        file_find_close()

        var _files = []
        for (var i = 0; i < array_length(_names); i++) {
            var _buf = buffer_load(_saves_dir + _names[i])
            if (!buffer_exists(_buf)) {
                continue
            }
            var _content = buffer_get_size(_buf) > 0 ? buffer_read(_buf, buffer_string) : ""
            buffer_delete(_buf)
            array_push(_files, {name: _names[i], content: _content})
        }
        return self.write_text_file(_target_file, json_stringify({files: _files}, true))
    }

    /// @param {String} _saves_dir
    /// @param {String} _source_file
    /// @returns {Real}
    static read_backup_file = function(_saves_dir, _source_file) {
        var _buf = buffer_load(_source_file)
        if (!buffer_exists(_buf)) {
            return kNativeErrUnknownFailure
        }
        var _text = buffer_get_size(_buf) > 0 ? buffer_read(_buf, buffer_string) : ""
        buffer_delete(_buf)

        var _json = undefined
        try {
            _json = json_parse(_text)
        } catch (_e) {
            return kNativeErrJsonParseFailed
        }
        if (!is_struct(_json) || !variable_struct_exists(_json, "files") || !is_array(_json.files)) {
            return kNativeErrJsonParseFailed
        }

        if (!string_ends_with(_saves_dir, "/")) {
            _saves_dir += "/"
        }
        if (!directory_exists(_saves_dir)) {
            directory_create(_saves_dir)
        }
        for (var i = 0; i < array_length(_json.files); i++) {
            var _entry = _json.files[i]
            if (!is_struct(_entry) || !variable_struct_exists(_entry, "name") || !variable_struct_exists(_entry, "content")) {
                return kNativeErrJsonParseFailed
            }
            // 只取文件名，防止备份里的 "../" 写到存档目录外面
            var _file_name = filename_name(string_replace_all(string(_entry.name), "\\", "/"))
            if (_file_name == "") {
                return kNativeErrJsonParseFailed
            }
            var _code = self.write_text_file(_saves_dir + _file_name, string(_entry.content))
            if (_code != 0) {
                return _code
            }
        }
        return 0
    }

    /// @description 按原样写入 UTF-8 文本，不追加结尾的 0 字节。
    /// @param {String} _path
    /// @param {String} _text
    /// @returns {Real}
    static write_text_file = function(_path, _text) {
        var _size = string_byte_length(_text)
        var _buf = buffer_create(max(1, _size), buffer_fixed, 1)
        if (_size > 0) {
            buffer_write(_buf, buffer_text, _text)
        }
        buffer_save_ext(_buf, _path, 0, _size)
        buffer_delete(_buf)
        return file_exists(_path) ? 0 : kNativeErrUnknownFailure
    }

    /// @description Windows 上 %LOCALAPPDATA%\FVM_Reborn 就是 GameMaker 的存档目录。
    ///              其他平台把 "\\FVM_Reborn\\saves" 这类写法换成 game_save_id 下的绝对路径。
    /// @param {String} _path
    /// @returns {String}
    static to_save_area_path = function(_path) {
        _path = self.to_posix_path(_path)
        while (string_starts_with(_path, "/")) {
            _path = string_delete(_path, 1, 1)
        }
        if (_path == "FVM_Reborn") {
            _path = ""
        } else if (string_starts_with(_path, "FVM_Reborn/")) {
            _path = string_delete(_path, 1, string_length("FVM_Reborn/"))
        }
        return self.save_area_root() + _path
    }

    /// @returns {String} 以 "/" 结尾的存档目录绝对路径
    static save_area_root = function() {
        var _root = self.to_posix_path(game_save_id)
        if (!string_ends_with(_root, "/")) {
            _root += "/"
        }
        return _root
    }

    /// @param {String} _path
    /// @returns {String}
    static to_posix_path = function(_path) {
        return string_replace_all(string(_path), "\\", "/")
    }

    /// @description 绝对路径转 file:// URL，空格和中文按 UTF-8 字节做百分号编码。
    /// @param {String} _path
    /// @returns {String}
    static path_to_file_url = function(_path) {
        var _hex = "0123456789ABCDEF"
        var _url = "file://"
        var _len = string_byte_length(_path)
        for (var i = 1; i <= _len; i++) {
            var _b = string_byte_at(_path, i)
            var _keep = (_b >= ord("0") && _b <= ord("9"))
                || (_b >= ord("A") && _b <= ord("Z"))
                || (_b >= ord("a") && _b <= ord("z"))
                || _b == ord("-") || _b == ord(".") || _b == ord("_") || _b == ord("~") || _b == ord("/")
            if (_keep) {
                _url += chr(_b)
            } else {
                _url += "%" + string_char_at(_hex, (_b >> 4) + 1) + string_char_at(_hex, (_b & 15) + 1)
            }
        }
        return _url
    }

}