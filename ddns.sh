#!/bin/bash

# CHANGE THESE
auth_email="user@example.com"
auth_key="xxxxxxxxxx" # found in cloudflare account settings
zone_name="example.com"
record_name="1.example.com" #An array of record name to update, the amount and order must be the same with the mac_addr

# MAYBE CHANGE THESE
# prefix_file="/tmp/ipv6_ddns/prefix.txt"
id_file="/tmp/ipv6_ddns/cloudflare.ids"
ip_file="/tmp/ipv6_ddns/ip.txt"
log_file="/tmp/ipv6_ddns/cloudflare.log"

# LOGGER
log() {
    if [ "$1" ]; then
        echo -e "[$(date)] - $1" >> $log_file
    fi
}

erase_double_colon() 
{
    if [ -z "$(echo $1 | grep '::')" ]
    then
        echo "$1"
    else
        count=$(echo $1 | sed 's/:/ /g' | wc -w)
        if [ -z "$(echo $1 | grep "^::")" ]
        then
            str_0=" "
        fi
        for ((i=0;i<8-$count;++i))
        do
            str_0="${str_0}0 "
        done
        echo "$(echo $1 | sed 's/:/ /g' | sed "s/  /$str_0/" | sed 's/ /:/g')"
    fi
}

# SCRIPT START


[ ! -d "/tmp/ipv6_ddns" ] && mkdir /tmp/ipv6_ddns


BasePath=$(cd `dirname ${BASH_SOURCE}` ; pwd)
BaseName=$(basename $BASH_SOURCE)
ShellPath="$BasePath/$BaseName"

if [ ! -z "$(ps | grep \"$ShellPath\" | grep -v grep)" ]
then
    kill -9 "$(ps | grep \"$ShellPath\" | grep -v grep | xargs)"
    rm -rf $id_file $ip_file $log_file
fi





#make sure to get the zone_id
echo "Getting zone id..."

if [ -f $id_file ] && [ $(wc -l $id_file | cut -d " " -f 1) == 2 ]; then
    zone_identifier=$(head -1 $id_file)
else
    zone_identifier_message=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$zone_name" -H "X-Auth-Email: $auth_email" -H "X-Auth-Key: $auth_key" -H "Content-Type: application/json")
    # echo "zone_identifier_message:$zone_identifier_message
    # "
    if [[ "$zone_identifier_message" == *"result\":\[\]"* ]]
    then
        log "No such zone, please check the name of your zone.\n$zone_identifier_message"
        echo -e "No such zone, please check the name of your zone."
        exit 1
    elif [[ "$zone_identifier_message" == *"\"success\":false"* ]]
    then
        log "The auth email and key may be wrong, please check again.\n$zone_identifier_message"
        echo -e "the auth email and key may be wrong, please check again."
        exit 1
    elif [[ "$zone_identifier_message" != *"\"success\":true"* ]]
    then
        log "Get zone id for $zone_name failed."
        echo -e "Get zone id for $zone_name failed."
        exit 1
    fi
    zone_identifier=$(echo $zone_identifier_message | grep -o '[a-z0-9]*' | head -3 | tail -1)
    echo "$zone_identifier" > $id_file
fi


unset ip
echo "Changing IP for record: ${record_name}..."
ip=$(ifconfig | grep Global | grep '[a-f0-9:]*' -o | grep '^2' | grep ':' | sort | xargs) #$(ifconfig | grep $prefix | grep -o '[a-z0-9:]*' | head -3 | tail -1)

if [ "$ip" = "" ]
then
    flag=1
    log "Empty ip address for the device, please check."
    echo -e "Empty ip address for the device, please check."
    continue
fi




if [ ! -f $ip_file ]
then
    echo "$ip" > $ip_file
else
    # 获取旧的IP
    old_ip=$(cat $ip_file)

    if [[ "$old_ip" == "$ip" ]]
    then
        echo "IP has not changed."
        log "IP has not changed."
        exit 0
    else
        echo "$ip" > $ip_file
    fi
fi

while true
do
    deleting_record_id_message=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$zone_identifier/dns_records?name=${record_name}" \
        -H "X-Auth-Email: $auth_email" \
        -H "X-Auth-Key: $auth_key" \
        -H "Content-Type: application/json")
    if [[ "$deleting_record_id_message" != *"success\":true"* ]]
    then
        log "Getting deleting record's id for ${record_name} failed, retrying..."
        echo -e "Getting deleting record's id for ${record_name} failed, retrying..."
        continue
    else
        break
    fi
done

#delete old records
echo "Deleting records for ${record_name}..."
deleting_record_id=$(echo $deleting_record_id_message | grep -o '[a-z0-9]*","type' | cut -d '"' -f 1 | xargs)
if [ ! -z "$deleting_record_id" ]
then
    deleting_record_id=($deleting_record_id)
    for ((j=0;j<${#deleting_record_id[@]};++j))
    do
        while true
        do
            deleting_message=$(curl -s -X DELETE "https://api.cloudflare.com/client/v4/zones/$zone_identifier/dns_records/${deleting_record_id[j]}" \
                -H "X-Auth-Email: $auth_email" \
                -H "X-Auth-Key: $auth_key" \
                -H "Content-Type: application/json")
            if [[ "$deleting_message" != *"success\":true"* ]]
            then
                log "Deleting record ${deleting_record_id[j]} for ${record_name} failed, retrying..."
                echo -e "Deleting record ${deleting_record_id[j]} for ${record_name} failed, retrying..."
                continue
            else
                break
            fi
        done
    done
fi

#create new record
echo "Creating records for ${record_name}..."
ip=($ip)
for ((j=0;j<${#ip[@]};++j))
do
    while true
    do
        create_message=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/${zone_identifier}/dns_records" \
            -H "X-Auth-Email: $auth_email" \
            -H "X-Auth-Key: $auth_key" \
            -H "Content-Type: application/json" \
            --data "{\"type\":\"AAAA\",\"name\":\"${record_name}\",\"content\":\"${ip[j]}\",\"ttl\":120,\"proxied\":false}")
        if [[ "$create_message" != *"success\":true"* ]]
        then
            log "Creating record ${record_name} for IP ${ip[j]} failed, retrying..."
            echo -e "Creating record ${record_name} for IP ${ip[j]} failed, retrying..."
            continue
        else
            break
        fi
    done
done

exit 0
