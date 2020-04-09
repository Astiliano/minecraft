#!/bin/bash

# What directory to create a directory for each server version.
main_dir="${HOME}/minecraft_servers"
pass=0
err() {
    echo "[!] Error: ${@}" 1>&2
    exit 1
}

# Required format: type (long/short) exit on error (exit/noexit) $command_to_run
# Example: echo_and_run -l -ne sleep 10
# Example: echo_and_run --long --noexit sleep 10
#   Type - short: Don't need to track background process;short and simple command
#   Type - long: Need to track background process; something that may take a few seconds
#   Exit on error - exit: If command fails, exit
#   Exit on error - noexit: Even if command fails, don't exit
# Note: If terminal is note wide enough, each "state" of spinner while print on new line
echo_and_run() { 
    case "${1}" in
    -l|--long)
       type="long"
       shift
       ;;
    -s|--short)
        type="short"
        shift
        ;;
    *)
        err "${@} - Specify (-l) long or (-s) short : echo_and_run --(long/short) --(exit/noexit) command"
        ;;
    esac 

    case "${1}" in
        -e|--exit)
            exit="yes"
            shift
            ;;
        -ne|--noexit)
            exit="no"
            shift
            ;;
        *)
            err "${@} - Specify (-e) exit or (-ne) no exit : echo_and_run --(long/short) --(exit/noexit) command"
            ;;
    esac 

    export cmd="${*}"
    if [[ "${type}" = "short" ]]; then
        echo -en "- [!] Running '${*}': "
        if ${cmd} &>/dev/null ; then
            echo "OK"
            return 0
        else
            echo "FAIL"
            if [[ "${exit}" = "yes" ]]; then err "Check command ${cmd}";fi
            return 1
        fi
    fi

    if [[ "${type}" = "long" ]]; then
        ${cmd} &>/dev/null &
        pid="${!}"

        text="- [!] Running ${*} :" # While waiting for command to exit, (c) will be added to line.
        while kill -0 "${pid}" &>/dev/null; do
            for state in '|' '/' '-' '\';do
                echo -ne "\r${text}(c): ${state}"
                sleep 0.25
            done
        done

        echo -ne "\r${text}(s): -" # While waiting for pid status, '(s): -' will be added to line.
        if wait "${pid}"; then  # Get exit status of PID
                echo -e "\r${text}(d): OK"
        else
                echo -e "\r${text}(d): FAIL"
                if [[ "${exit}" = "yes" ]]; then err "Check command ${cmd}";fi # Did user want script to exit if it failed
                err "Invalid status grabbed: ${result}"
        fi
    fi
}


agree_eula() { # eula.txt requires `eula=false` be changed to `eula=true` for server to run.
    echo -e "[!] CONFIRMATION REQUIRED (One Time Only) :::\n"\
    "By typing 'I AGREE' you are indicating your agreement to our EULA (https://account.mojang.com"\
    "/documents/minecraft_eula)"
    until grep "eula=TRUE" "${eula_file}" &> /dev/null; do
        read -p "[!] Type 'I AGREE' or press CTRL+C to exit: " eula
        if [[ "${eula}" = "I AGREE" ]]; then
        sed -ir 's/^eula=\w\+/eula=TRUE/g' "${eula_file}"
        fi
    done
}

check_eula() {
    echo -n "[!] Checking if ${eula_file} exists: "
    if [[ -f "${eula_file}" ]]; then
        echo "OK"
        echo -n "[!] Checking if eula has been signed: "
        if grep "eula=TRUE" "${eula_file}" &> /dev/null; then
            echo "OK"
        else
            if [[ "${pass}" -gt 2 ]]; then err "Eula sign check is looping";fi # Max allow 3 tries
            pass=$(expr "${pass}" + 1)
            echo "FAIL"
            agree_eula
            check_eula
        fi
    else
        echo "FAIL"
        if [[ "${pass}" -gt 0 ]]; then
            err "Eula not found even after attempting to startup the server"
        fi
        
        echo "[!] In order to create eula, will startup the server once (don't worry it 'should' immediately close because of unsigned eula)"
        echo_and_run --long --exit java -Xms512M -Xmx3G -jar "forge-${version}-${build}.jar" nogui
        check_eula
    fi
}

server_status() {
    installed_servers=$( find "${main_dir}" -maxdepth 2 -regex ".*\.jar" | grep -v installer )
    installed_dirs=( $(<<< "${installed_servers}" grep -oP "/.*/" | uniq) )
    echo -e "\n ======== Installed Servers ========\n"
    for dir in "${installed_dirs[@]}"; do
        echo "[!] ${dir}"
        eula_file="${dir}/eula.txt"
        echo_and_run --short --exit cd "${dir}" > /dev/null
        for jar in $(echo "${installed_servers}" | grep "${dir}" | sed 's,\/.*\/,,g'); do
            if ps aux &>/dev/null | grep -P "jar.*\-jar.*${jar}" ; then
                srv_status="Running"
            else
                srv_status="Not Running"
            fi
            printf "\t%-30s %-5s %-15s\n" "$jar" ':::' "${srv_status}"
        done
        echo
        check_eula
        check_log
    done
}

_load_eula() {
    echo -ne "\t[!] eula.txt file load: "
    if grep "Failed to load eula.txt" "${log_file}"&>/dev/null; then 
        echo "FAIL"
        return 1
    else
        echo "OK"
        return 0
    fi
}

_spawn_start() {
    echo -ne "\t[!] Preparing spawn area check: "
    if grep "Preparing spawn area:" "${log_file}" &>/dev/null; then 
        echo "OK"
        return 0
    else
        echo "FAIL"
        return 1
    fi
}

_spawn_complete() {
    echo -ne "\t[!] Area spawn completion check: "
    if grep "Time elapsed:" "${log_file}"&>/dev/null; then 
        echo "OK"
        return 0
    else
        echo "FAIL"
        return 1
    fi
}

_server_stop() {
        echo -ne "\t[!] Checking log for stopped server: "
        if grep "Stopping server" "${log_file}"&>/dev/null; then 
            echo "FAIL"
        else
            echo "OK"
        fi
}

check_log() {
    log_file="${dir}logs/latest.log"
    echo -e "\n[!] Log check for: ${log_file}\n-----------------------------"
    
    _load_eula
    _spawn_start
    _spawn_complete
    _server_stop
    
    echo -e "\n[!] Last 5 entries\n-----------------------------"
    tail -5 "${log_file}"
    echo -e "\n\n\n"
}


server_start() {
    if installed_servers=( $(find "${main_dir}" -maxdepth 2 -regex ".*\.jar" | grep -v installer | grep jar) ); then
        echo "[!] Select server to start (Forge = Mods / minecraft_server = Vanilla;no mods)"
        select run_server_version in "${installed_servers[@]}"; do 
            if [[ "${REPLY}" -gt "${#installed_servers[@]}" ]]; then
                echo "[!] WARN : Please make a proper selection."
            else
                echo "[!] Selected Installed Server: ${run_server_version}"
                esc_main_dir=$(<<< "${main_dir}" sed 's/\//\\\//g')
                server_version=$(<<< "${run_server_version}" sed "s/${esc_main_dir}//g" | cut -d'/' -f2)
                break
            fi
        done
    fi
    echo_and_run --short --exit cd "${main_dir}/${server_version}"

    if screen -ls | grep "minecraft_${server_version}" &> /dev/null; then
        err Screen session exists for that server, type \'screen -x minecraft_${server_version}\' to connect to it.
    fi

    echo "[!] Starting server in screen as: minecraft_${server_version}"
    screen -dmS "minecraft_${server_version}" java -Xms1024m -Xmx3072m -jar "${run_server_version}" nogui

    sleep 5
    echo -e "\n[!] Checking server startup process\n--------------"
    
    log_file="${main_dir}/${server_version}/logs/latest.log"

    text="[!]Starting Minecraft Server"
    SECONDS=0
    TIMEOUT=60
    until grep "Starting minecraft server" "${log_file}" &>/dev/null; do
        if [[ "${SECONDS}" -gt "${TIMEOUT}" ]]; then
            err Server took too long to start
        fi
        for state in '|' '/' '-' '\';do
            echo -ne "\r${text} : ${state}"
            sleep 0.25
        done
    done
     echo -e "\r${text} : OK"

    text="[!]Preparing Level"
    SECONDS=0
    TIMEOUT=60
    echo -n "${text}"
    until grep "Preparing level" "${log_file}" &>/dev/null; do
        if [[ "${SECONDS}" -gt "${TIMEOUT}" ]]; then
            err Server took too long to reach \'Preparing Level\'
        fi
        for state in '|' '/' '-' '\';do
            echo -ne "\r${text} : ${state}"
            sleep 0.25
        done
    done
    echo -e "\r${text} : OK"

    text="[!]Preparing Spawn Area: Complete "
    SECONDS=0
    TIMEOUT=180
    echo -n "[!] Preparing Spawn Area"
    until grep "Time elapsed:" "${log_file}" &>/dev/null; do
        if [[ "${SECONDS}" -gt "${TIMEOUT}" ]]; then
            err Server took too long to complete \'Preparing Spawn Area\'
        fi
        for state in '|' '/' '-' '\';do
            echo -ne "\r[!]$(grep "Preparing spawn area" "${log_file}" | grep -oP "Preparing spawn area:.*%" | tail -1)"
            sleep 0.25
        done
    done
    echo -e "\r${text}"
}

server_stop() {
    echo "boop"
}

main() {
    echo -n "[!] Verify Debian Distro: "
    if [[ $(cat /proc/version) =~ "debian"  ]]; then 
      echo "OK"
    else
      echo "FAIL"
      err "Distro not found to be Debian"
    fi

    echo_and_run --long --exit sudo apt-get update -y 
    echo_and_run --long --exit sudo apt-get upgrade -y 
    echo_and_run --long --exit sudo apt-get install -y software-properties-common 
    echo_and_run --long --exit sudo apt-get install -y default-jre-headless 
    echo_and_run --long --exit sudo apt-get install -y screen
    echo_and_run --long --exit sudo apt-get install -y telnet
  
    echo -n "[!] Checking if ${main_dir} directory exists: "
    if [[ -d "${main_dir}" ]]; then
        echo "OK"
    else
        echo "FAIL - creating"
        echo_and_run --short --exit mkdir ${main_dir}
    fi
  
    server_versions_raw=$(curl -s https://files.minecraftforge.net/maven/net/minecraftforge/forge/index_1.1.html)
    server_versions=( $(<<< "${server_versions_raw}" grep -o "index_.*\.[0-9]\.html"| sed -e 's/index_//g;s/\.html//g') )

    until [[ "${proceed}" = "yes"  ]]; do
        echo -e "\n[!] Select which Server Version to download (Next question will be build version)"
        select version in "${server_versions[@]}"; do 
        if [[ "${REPLY}" -gt "${#server_versions[@]}" ]]; then
            echo "[!] WARN : Please make a proper selection."
        else
            echo "[!] Selected Server Version: ${version}"
        break
        fi
        done
    
        server_builds_raw=$(curl -s https://files.minecraftforge.net/maven/net/minecraftforge/forge/index_"${version}".html)
        server_builds_latest=$(<<< "${server_builds_raw}" grep -i "Download Latest" -A1 | grep built | sed -e's/[-<>!]//g;s/\/small//g;s/small//g' | xargs)
        server_builds_recommended=$(<<< "${server_builds_raw}" grep -i "Download Recommended" -A1 | grep built | sed -e's/[-<>!]//g;s/\/small//g;s/small//g' | xargs)
        server_builds=( $(<<< "${server_builds_raw}" grep "Gradle" | grep -oP "\d+\.\d+\.\d+'" | sed "s/'//g") )
        echo -e "\n[!] Select which build to download"
        if [[ -n "${server_builds_recommended}" ]]; then
            echo -e "\t-- Recommended: ${server_builds_recommended}"
        fi

        if [[ -n "${server_builds_latest}" ]]; then
            echo -e "\t-- Latest:      ${server_builds_latest}"
        fi
    
        echo
    
        select build in "${server_builds[@]}"; do 
            if [[ "${REPLY}" -gt "${#server_builds[@]}" ]]; then
                echo "[!] WARN : Please make a proper selection."
            else
                echo "[!] Selected Build: ${build}"
                break
            fi
        done
    
        echo -e "\n[!] Final Options\n\tServer Version: ${version}\n\tServer Build:   ${build}\n" 
        read -p "[!] Is this correct? (yes/no): " proceed
    done

    eula_file="${main_dir}/${version}/eula.txt"
    echo -n "[!] Checking if ${main_dir}/${version} directory exists: "
    if [[ -d "${main_dir}/${version}" ]]; then
        echo "OK"
    else
        echo "FAIL"
        echo_and_run --short --exit mkdir "${main_dir}/${version}"
    fi

    echo -n "[!] Checking if ${main_dir}/${version}/mods directory exists: "
    if [[ -d "${main_dir}/${version}/mods" ]]; then
        echo "OK"
    else
        echo "FAIL"
        echo_and_run --short --exit mkdir "${main_dir}/${version}/mods"
    fi
  
    echo_and_run --short --exit cd ${main_dir}/${version}

    echo -n "[!] Checking if installer exists: "
    if [[ -f "${main_dir}/${version}/forge-${version}-${build}-installer.jar" ]]; then
        echo "Found - Cleaning Up"
        echo_and_run --short --exit "rm ${main_dir}/${version}/forge-*-installer.jar"
    else
        echo "Not Found - Clean"
    fi
  
    echo_and_run --long --exit wget -q "https://files.minecraftforge.net/maven/net/minecraftforge/forge/${version}-${build}/forge-${version}-${build}-installer.jar"
    echo_and_run --long --exit java -jar "forge-${version}-${build}-installer.jar" --installServer
    check_eula
    echo -e "\n[!] All Done! When ready to start your server, just run '${0} -start'"
}

case "${@}" in
    -setup)
        main
        ;;
    -status)
        server_status
        ;;
    -start)
        server_start
        ;;
    -stop)
        server_stop
        ;;
    *)
        echo "This script is meant to simplify setting up a minecraft server on a linux debian host

        Options:
            -setup   : Do this if running for the first time
            -status  : Provides server status (running/stopped)
            -start   : Start minecraft server
            -stop    : Stop minecraft server"
        exit 1
        ;;
esac
