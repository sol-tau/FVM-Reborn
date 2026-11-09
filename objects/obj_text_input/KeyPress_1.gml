// obj_text_input 键盘按下事件
if (active) {
    // 获取按下的键
    var key = keyboard_key;
    var char = keyboard_lastchar;
	//show_debug_message(keyboard_lastchar)
    
    // 只处理可打印字符；v7.3 去掉 <=126 上限，以接收 IME 提交的中文
    // （控制字符仍被 ord(char) >= 32 挡掉）
    if (char != "" && ord(char) >= 32 && string_length(text) < max_length) {
        text += char;
    }
    // macOS 上退格、方向键这类不产生字符的键不会刷新 keyboard_lastchar，
    // 不清空的话，按这些键会把上一个字符再加一遍（退格看起来就删不掉）
    if (os_type != os_windows) {
        keyboard_lastchar = "";
    }
}