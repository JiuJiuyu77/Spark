#!/bin/sh
# sign.plist —— THEOS 打包时用于 ldid -S 的权限文件
# 需要「起子进程 + 读写整个文件系统」，否则真机编译时 make/clang 会直接被杀掉。
{
	echo '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
	echo '<plist version="1.0"><dict>'
	echo '<key>platform-application</key><true/>'
	echo '<key>com.apple.private.security.no-sandbox</key><true/>'
	echo '<key>com.apple.private.security.storage.AppDataContainers</key><true/>'
	echo '<key>com.apple.private.cs.debugger</key><true/>'
	echo '<key>get-task-allow</key><true/>'
	echo '<key>task_for_pid-allow</key><true/>'
	echo '<key>com.apple.security.exception.process-info</key><true/>'
	echo '<key>com.apple.security.cs.allow-jit</key><true/>'
	echo '<key>run-unsigned-code</key><true/>'
	echo '<key>com.apple.private.security.storage.MobileDocuments</key><true/>'
	echo '<key>com.apple.security.exception.files.absolute-path.read-only</key><array><string>/</string></array>'
	echo '</dict></plist>'
} > "$(dirname "$0")/sign.plist"
exit 0
