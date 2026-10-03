# ========================================================
# 安路 TD 工程自动同步脚本 (update_project.tcl) - 增强版
# 作用：自动添加新增的源码，并移除已被 Git 删除的源码
# ========================================================

set src_dir "../src"
set constr_dir "../constrs"

puts "======== 开始双向同步工程 ========"

# --- 1. 收集磁盘上真实存在的文件 ---
set disk_files {}
if {[file exists $src_dir]} {
    set v_files [glob -nocomplain -directory $src_dir *.v]
    set sv_files [glob -nocomplain -directory $src_dir *.sv]
    set disk_files [concat $disk_files [concat $v_files $sv_files]]
}
if {[file exists $constr_dir]} {
    set fdc_files [glob -nocomplain -directory $constr_dir *.fdc]
    set tcl_files [glob -nocomplain -directory $constr_dir *.tcl]
    set disk_files [concat $disk_files [concat $fdc_files $tcl_files]]
}

# 把磁盘绝对路径统一格式，方便比对
set normalized_disk_files {}
foreach f $disk_files {
    lappend normalized_disk_files [string map {\\ /} $f]
}

# --- 2. 添加新文件（磁盘上有，但工程里没有的） ---
puts "--- 正在检查新增文件 ---"
foreach file $disk_files {
    set file_path [string map {\\ /} $file]
    if {[catch {add_file -path $file_path} result]} {
        # 已经存在，跳过
    } else {
        puts "成功添加: $file_path"
    }
}

# --- 3. 移除过期文件（工程里有，但磁盘上已被删除的） ---
puts "--- 正在检查已删除的文件 ---"
# 注意：不同版本的安路TD获取工程文件列表的命令可能不同
# 这里假设命令为 get_files，如果报错请在Console里查看实际命令并替换
if {[catch {set project_files [get_files]} result]} {
    puts "警告: 无法获取工程文件列表 (get_files命令不兼容)。请手动检查工程树中的过期文件。"
} else {
    foreach proj_file $project_files {
        set norm_proj_file [string map {\\ /} $proj_file]
        
        # 只处理属于 src 或 constrs 目录下的文件
        if {[string match "*$src_dir*" $norm_proj_file] || [string match "*$constr_dir*" $norm_proj_file]} {
            # 如果工程里的文件，不在磁盘现存的文件列表中，说明它被Git删除了
            if {[lsearch -exact $normalized_disk_files $norm_proj_file] == -1} {
                if {[catch {remove_file -path $norm_proj_file} remove_result]} {
                    puts "移除失败: $norm_proj_file"
                } else {
                    puts "成功移除过期文件: $norm_proj_file"
                }
            }
        }
    }
}

puts "======== 同步完成！请按 Ctrl+S 保存工程 ========"