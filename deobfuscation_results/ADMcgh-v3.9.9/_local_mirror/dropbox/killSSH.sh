#!/bin/bash
#CREADOR Henry Chumo | 06/06/2022
#REFACTORY | 01/07/2024
#Alias : @ChumoGH
# NUNCA  DEJES DE APRENDER
# POWER BY @CHUMOGH
# -*- ENCODING: UTF-8 -*-
#!/bin/bash


[[ ! -d /etc/ADMcgh/limit ]] && {
[[ $(dpkg --get-selections|grep -w "at"|head -1) ]] || apt-get install at -y &>/dev/null
mkdir /etc/ADMcgh/limit
print_center -verm2 'LIMITADOR SSH /DROPBEAR!!!\n DEFINA EL TIEMPO PARA EL LIMITADOR \n '
msg -bar3
echo -ne " LIMITAR EN MINUTOS : "; read _timeK
[[ -z ${_timeK} ]] && _timeK='1'
msg -bar3
echo "${_timeK}" > /etc/ADMcgh/limit/interval
print_center -verm2 'DESBLOQUEO AUTOMATIO!!!\n DEFINA EL TIEMPO DE DESBLOQUEO AUTOMATICO \n PARA USUARIOS LIMITADOS Y BLOQUEADOS \n (PRESIONA ENTER PARA DESBLOQUEO MANUAL)'
msg -bar3
echo -ne " UNLOCK EN MINUTOS : "; read _timeuUL
[[ -z ${_timeuUL} ]] && _timeuUL='0'
_timeK=$(($_timeK * 60))
echo "${_timeuUL}" > /etc/ADMcgh/limit/unlock
	[[ -e /etc/systemd/system/killadm.service ]] && {
		echo -e "[Unit]
		Description=KillLogin Service by @ChumoGH
		After=network.target
		StartLimitIntervalSec=0

		[Service]
		Type=simple
		User=root
		WorkingDirectory=/root
		ExecStart=$(which bash) /bin/killssh
		Restart=always
		RestartSec=${_timeK}s

		[Install]
		WantedBy=multi-user.target" > /etc/systemd/system/killadm.service
		systemctl daemon-reload &>/dev/null
		systemctl restart killadm &>/dev/null 
	}
}

droppids(){
  port_dropbear=`ps aux|grep 'dropbear'|awk NR==1|awk '{print $17;}'`
  log=/var/log/auth.log
  loginsukses='Password auth succeeded'
  pids=`ps ax|grep 'dropbear'|grep " $port_dropbear"|awk -F " " '{print $1}'`
  for pid in $pids; do
    pidlogs=`grep $pid $log |grep "$loginsukses" |awk -F" " '{print $3}'`
    i=0
    for pidend in $pidlogs; do
      let i=i+1
    done
    if [ $pidend ];then
       login=`grep $pid $log |grep "$pidend" |grep "$loginsukses"`
       PID=$pid
       user=`echo $login |awk -F" " '{print $10}' | sed -r "s/'/ /g"`
       waktu=`echo $login |awk -F" " '{print $2"-"$1,$3}'`
       while [ ${#waktu} -lt 13 ]; do
           waktu=$waktu" "
       done
       while [ ${#user} -lt 16 ]; do
           user=$user" "
       done
       while [ ${#PID} -lt 8 ]; do
           PID=$PID" "
       done
       echo "$user $PID $waktu"
    fi
done
}

sshmonitor(){
  h=1
  unlimit=$(cat /etc/ADMcgh/limit/unlock)
    for i in `echo "$user_type"`; do

        user="$i"
        s2ssh="$(cat /etc/passwd|grep -w "$i"|awk -F ':' '{print $5}'|cut -d ',' -f1)"

        if [[ "$(cat /etc/passwd| grep -w $user| wc -l)" = "1" ]]; then
          sqd="$(ps -u $user | grep sshd | wc -l)"
        else
          sqd=00
        fi
        [[ "$sqd" = "" ]] && sqd=0

        if [[ -e /etc/openvpn/openvpn-status.log ]]; then
          ovp="$(cat /etc/openvpn/openvpn-status.log | grep -E ,"$user", | wc -l)"
        else
          ovp=0
        fi

        if netstat -nltp|grep 'dropbear'> /dev/null;then
          drop="$(droppids | grep -w "$user" | wc -l)"
        else
          drop=0
        fi

        cnx=$(($sqd + $drop))
        conex=$(($cnx + $ovp))

        if [[ "$conex" -gt "$s2ssh" ]]; then
        	pkill -u $user
        	droplim=`droppids|grep -w "$user"|awk '{print $2}'` 
        	kill -9 $droplim &>/dev/null
        	usermod -L $user
        	echo "$user $(printf '%(%H:%M:%S)T') $conex/$s2ssh" >> "$HOME/limiter.log"
          [[ $unlimit -le 0 ]] && continue || at now +${unlimit} minutes <<< "usermod -U $user" &>/dev/null
        fi
      done
      touch /etc/ADMcgh/limit/interval
      timer=$(cat /etc/ADMcgh/limit/interval)
      [[ -z ${timer} ]] && timer="1"
      [[ -e /etc/systemd/system/killadm.service ]] || at now +${timer} minutes <<< "/bin/killssh" &>/dev/null
      [[ -z $(cat "/var/spool/cron/crontabs/root"|grep "killssh") ]] && echo "@reboot root /bin/killssh" >> /var/spool/cron/crontabs/root
}

expired(){
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
    while read line; do
      userDate=$(chage -l "$line"|sed -n '4p'|awk -F ': ' '{print $2}')
      if [[ $(date '+%s') -gt $(date '+%s' -d "$userDate") ]]; then
        if [[ $(passwd --status $line|cut -d ' ' -f2) = "P" ]]; then  
          usermod -L $line
          echo "$line $(printf '%(%H:%M:%S)T') expirado" >> "$HOME/limiter.log"
        fi    
      fi
    done <<< $(echo "$user_type")
}

all_user=$(cat /etc/passwd|grep 'home'|grep 'false'|grep -v 'syslog'|grep -v '::/')
case $1 in
    -s|--ssh)user_type=$(echo "$all_user"|grep -v 'HWID\|TOKEN'|awk -F ':' '{print $1}') && expired;;
   -h|--HWID)user_type=$(echo "$all_user"|grep -w 'HWID'|awk -F ':' '{print $1}') && expired;;
  -t|--TOKEN)user_type=$(echo "$all_user"|grep -w 'TOKEN'|awk -F ':' '{print $1}') && expired;;
           *)user_type=$(echo "$all_user"|grep -v 'HWID\|TOKEN'|awk -F ':' '{print $1}') && sshmonitor;;
esac