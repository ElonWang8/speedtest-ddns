#!/bin/bash
# Cloudflare 账号信息
API_EMAIL="<email>"
API_KEY="<自行查找>"
ZONE_ID="<自行查找>"
DOMAIN="<自己的域名>"

# PushDeer 信息，从环境变量中获取 PUSHKEY，自行获取
PUSHKEY="${PUSHKEY:-PDU26886QaqPVSZiO1YB1DnMg2HclNYMUxlG6ueCc}"

# 确认 CloudflareST 可执行文件有执行权限
chmod +x ./CloudflareST

# TS工具
CLOUDFLARE_SPEED_TEST="./CloudflareST" # 假设 CloudflareST 可执行文件放在当前目录

# 运行 CloudflareSpeedTest 并保存结果到 result.csv
chmod +x $CLOUDFLARE_SPEED_TEST
$CLOUDFLARE_SPEED_TEST -o result.csv -tp 80 -url http://speedtest.elonbot.eu.org/ # 在这里添加 -tp 参数，将测速端口指定为 443

# 获取 result.csv 文件中的前五个IP
FIRST_IP=$(awk -F, 'NR==2 {print $1}' result.csv)
SECOND_IP=$(awk -F, 'NR==3 {print $1}' result.csv)
THIRD_IP=$(awk -F, 'NR==4 {print $1}' result.csv)
FOURTH_IP=$(awk -F, 'NR==5 {print $1}' result.csv)
FIFTH_IP=$(awk -F, 'NR==6 {print $1}' result.csv)
echo "筛选出的前五个 IP: $FIRST_IP, $SECOND_IP, $THIRD_IP, $FOURTH_IP, $FIFTH_IP"

# 获取 Cloudflare 的 DNS 记录
DNS_RECORDS=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?type=A&name=$DOMAIN" \
    -H "X-Auth-Email: $API_EMAIL" \
    -H "X-Auth-Key: $API_KEY" \
    -H "Content-Type: application/json")

# 提取现有的记录ID和IP
RECORD_IDS=($(echo $DNS_RECORDS | jq -r '.result[] | select(.type == "A") | .id'))
EXISTING_IPS=($(echo $DNS_RECORDS | jq -r '.result[] | select(.type == "A") | .content'))

# 函数：创建或更新 A 记录
create_or_update_record() {
    local ip=$1
    local record_id=$2

    if [ -z "$record_id" ]; then
        # 创建新的 A 记录
        result=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
            -H "X-Auth-Email: $API_EMAIL" \
            -H "X-Auth-Key: $API_KEY" \
            -H "Content-Type: application/json" \
            --data '{"type":"A","name":"'"$DOMAIN"'","content":"'"$ip"'","ttl":60,"proxied":false}')
    else
        # 更新现有 A 记录
        result=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$record_id" \
            -H "X-Auth-Email: $API_EMAIL" \
            -H "X-Auth-Key: $API_KEY" \
            -H "Content-Type: application/json" \
            --data '{"type":"A","name":"'"$DOMAIN"'","content":"'"$ip"'","ttl":60,"proxied":false}')
    fi
    echo $result
}

# 更新或创建记录
update_result1=$(create_or_update_record $FIRST_IP ${RECORD_IDS[0]})
update_result2=$(create_or_update_record $SECOND_IP ${RECORD_IDS[1]})
update_result3=$(create_or_update_record $THIRD_IP ${RECORD_IDS[2]})
update_result4=$(create_or_update_record $FOURTH_IP ${RECORD_IDS[3]})
update_result5=$(create_or_update_record $FIFTH_IP ${RECORD_IDS[4]})

# 如果现有记录少于五个，创建新的记录
if [ ${#RECORD_IDS[@]} -lt 5 ]; then
    for ((i=${#RECORD_IDS[@]}; i<5; i++)); do
        new_ip_var="IP_$((i+1))"
        new_ip="${!new_ip_var}"
        update_result=$(create_or_update_record $new_ip "")
        echo "创建新记录结果: $update_result"
    done
fi

echo "DDNS更新结果: $update_result1, $update_result2, $update_result3, $update_result4, $update_result5"

# 发送 PushDeer 推送
PUSHDEER_MESSAGE=$(jq -n --arg domain "$DOMAIN" --arg first_ip "$FIRST_IP" --arg second_ip "$SECOND_IP" --arg third_ip "$THIRD_IP" --arg fourth_ip "$FOURTH_IP" --arg fifth_ip "$FIFTH_IP" --arg update_result1 "$update_result1" --arg update_result2 "$update_result2" --arg update_result3 "$update_result3" --arg update_result4 "$update_result4" --arg update_result5 "$update_result5" \
'{pushkey: env.PUSHKEY, text: "DDNS 更新\n域名: \($domain)\n新IP: \($first_ip), \($second_ip), \($third_ip), \($fourth_ip), \($fifth_ip)\n更新结果: \($update_result1), \($update_result2), \($update_result3), \($update_result4), \($update_result5)"}')

curl -s --retry 3 -X POST -H 'Content-Type: application/json' -d "$PUSHDEER_MESSAGE" https://api2.pushdeer.com/message/push
