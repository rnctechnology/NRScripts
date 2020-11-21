#
# Sample Recipe:: mount_disks_new
# To mount os and data diskes
#

nodeList = []
if node[:disks]!=nil
  nodeList = node[:disks]
end
shell_command_out=""
shell_command="blkid -o device"
blkidList = Mixlib::ShellOut.new("#{shell_command}")
blkidList.run_command
shell_command_out=blkidList.stdout
log "shell command: #{shell_command}"
log "shell outptut: #{shell_command_out}"
allDiskList = shell_command_out.split("\n")

osDisks=[]
dataDisks =[]
dataDisksUmount =[]
log "diskList: #{allDiskList}"
for diskVal in allDiskList
  if diskVal=~/sda/ || diskVal=~/sda\d+/
    osDisks.push(diskVal)
  else
    dataDisks.push(diskVal)
    dataDisksUmount.push("\""+diskVal+"\"")
  end
end
log "osDisks: #{osDisks}"
log "dataDisks: #{dataDisks}"

if dataDisks.count == nodeList.count
  index = 0
  for umountListVal in dataDisksUmount
    bash "Unmount #{umountListVal}" do
      code  <<-EOH
        umount #{umountListVal}
      EOH
      returns [0, 1]
    end
  end
  log "sleeping 10s"
  sleep 10
  
  shell_command_out=""
  shell_command="df -H"
  df = Mixlib::ShellOut.new("#{shell_command}")
  df.run_command
  shell_command_out=df.stdout
  log "df -H post unmounting: #{shell_command_out}"

  nodeList.each do |disk|
    directory disk[:mount_point] do
      recursive true
      action :create
    end
    log "Mount options: #{disk[:mount_options]}" if disk[:mount_options]

    if  disk[:force]
      ruby_block "modify fstab" do
        block do
          file = Chef::Util::FileEdit.new("/etc/fstab")
          file.search_file_delete_line("#{disk[:mount_point]}")
          file.write_file
        end
      end

    end
    shell_command_out=""
    shell_command="tune2fs -L #{disk[:mount_point]} #{dataDisks[index]}"
    df = Mixlib::ShellOut.new("#{shell_command}")
    df.run_command
    shell_command_out=df.stdout
    log "changing labels: #{shell_command_out}"

    log "Mounting #{disk[:mount_point]} with #{dataDisks[index]} and #{disk[:fstype]} and #{disk[:mount_options]}"
    shell_command_out=""
    shell_command="blkid -o value -s TYPE #{dataDisks[index]}"
    df = Mixlib::ShellOut.new("#{shell_command}")
    df.run_command
    blkidVal=df.stdout
    blkidVal=blkidVal.strip
    log "blkidVal : #{blkidVal}"
    log "disk[:fstype] : #{disk['fstype']}"
    ifSameFs=false
    if disk[:fstype]=~/#{blkidVal}/
      ifSameFs=true
    end
    log "ifSameFs : #{ifSameFs}"
    
    mount disk[:mount_point] do
      not_if "grep -qs '#{disk[:mount_point]}' /proc/mounts"
      only_if "blkid -o value -s TYPE #{dataDisks[index]}"
      device dataDisks[index]
      fstype disk[:fstype]
      options disk[:mount_options] if disk[:mount_options]
      if disk[:format] && !ifSameFs
         action :enable
       else
         action :mount
         action :enable
       end
       
    end

    bash "Format #{dataDisks[index]}" do
      case disk[:fstype]
      when 'xfs'
        code "mkfs.xfs #{disk[:format_options]} #{dataDisks[index]}"
      when 'ext3'
        code "mkfs.ext3 #{disk[:format_options]} #{dataDisks[index]}"
      when 'ext4'
        code "mkfs.ext4 #{disk[:format_options]} #{dataDisks[index]}"
      end
      returns [0, 1]
      timeout 72000
      only_if { disk[:format] && !ifSameFs}
      notifies :mount, "mount[#{disk[:mount_point]}]", :immediately
    end
      
    index = index + 1
  end
else
  log "Count mismatch."
  log "dataDisks: #{dataDisks}"
  log "nodeList: #{nodeList}"
  log "dataDisks count: #{dataDisks.count}"
  log "dataDisks count: #{nodeList.count}"
end

node.set['disks_new'] = ''
node.save