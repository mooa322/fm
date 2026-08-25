#!/bin/bash
user=$1
type=$2

user_exist() {
    [[ "$(grep -wc $user /etc/passwd)" != '0' ]] && {
        echo $user
    } || {
        echo 'Not exist'
    }
}

cont_online() {
	limit=$(cat /etc/passwd|grep -w "$user"|awk -F ':' '{print $5}'|cut -d ',' -f1)
	[[ ${_limit} = @(HWID|TOKEN) ]] && _limit='1'
    conssh="$(ps -u $user | grep sshd | wc -l)"
    [[ -z $limit ]] && limit="1"
    #[[ $conssh -gt $limit ]] && kill -9 $user
    echo $conssh
}

limiter_user() {
    limit=$(cat /etc/passwd | grep -w ${user} | awk -F ':' '{split($5, a, ","); print a[1]}')
	[[ ${_limit} = @(HWID|TOKEN) ]] && _limit='1'
    echo $limit
}

check_data() {
    datauser=$(chage -l $user | grep -i co | awk -F : '{print $2}')
    dat="$(date -d"$datauser" '+%d/%m/%Y')"
    echo $dat
}

check_dias() {
    datauser=$(chage -l $user | grep -i co | awk -F : '{print $2}')
    dat="$(date -d"$datauser" '+%Y-%m-%d')"
    data=$(echo -e "$((($(date -ud $dat +%s) - $(date -ud $(date +%Y-%m-%d) +%s)) / 86400))")
    echo $data
}

check_new_data() {
    [[ "$(grep -wc $user /etc/passwd)" != '0' ]] && {
        datauser=$(chage -l $user | grep -i co | awk -F : '{print $2}')
        dat="$(date -d"$datauser" '+%Y%m%d')"
        echo $dat
    } || {
        echo 'Not exist'
    }
}

datacheck_new() {
    [[ "$(grep -wc $user /etc/passwd)" != '0' ]] && {
        datauser=$(chage -l $user | grep -i co | awk -F : '{print $2}')
        dat="$(date -d"$datauser" '+%d%m%Y')"
        echo $dat
    } || {
        echo 'Not exist'
    }
}


[[ ${type} = 1 ]] && user_exist
[[ ${type} = 2 ]] && cont_online
[[ ${type} = 3 ]] && limiter_user
[[ ${type} = 4 ]] && check_data
[[ ${type} = 5 ]] && check_dias
[[ ${type} = 6 ]] && check_new_data
[[ ${type} = 7 ]] && datacheck_new