#!/bin/bash

# What directory to create a directory for each server version.
main_dir="${HOME}/minecraft_servers"

# Main file to send pid - cmd to for tracking
pid_file="/tmp/pid_tracking_file"

err() {
    echo "[!] Error: ${@}" 1>&2
    exit 1
}

# Runs command, grabs pid and exit status
background() {
	${cmd} &>/dev/null &
	pid="${!}"
	echo "${pid} - ${cmd}" > ${pid_file}
	wait "${pid}"
	echo "${?}" > ${pid_file}.${pid}
}

pid_file_cleanup() {
    rm ${pid_file:-rm_safeguard}* &>/dev/null # Cleanup any old pid files both main and sub.
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
        pid_file_cleanup
        background &
        pid=$(grep "${cmd}" "${pid_file}" | awk '{print $1}')

        # While waiting for command to exit, (c) will be added to line.
        text="- [!] Running ${*} :"
        while kill -0 "${pid}" &>/dev/null; do
            for state in '|' '/' '-' '\';do
                echo -ne "\r${text}(c): ${state}"
                sleep 0.25
            done
        done

        # While waiting for pid file to be created, (f) will be added to line.
        until [[ -f ${pid_file}.${pid} ]]; do
                for state in '|' '/' '-' '\'; do
                    echo -ne "\r${text}(f): ${state}"
                    sleep 0.25
                done
        done

        # Once it's past checking for pid file, (d) will be added to line.
        result=$(cat ${pid_file}.${pid})
		pid_file_cleanup
        case "${result}" in
        0) 
            echo -e "\r${text}(d): OK"
            return 0
            ;;
        1)
            echo -e "\r${text}(d): FAIL"
            if [[ "${exit}" = "yes" ]]; then err "Check command ${cmd}";fi
            return 1
            ;;
        *)
            err "Invalid status grabbed: ${result}"
            ;;
        esac
    fi
}

# eula.txt requires `eula=false` be changed to `eula=true` for server to run.
agree_eula() {
	echo -e "[!] CONFIRMATION REQUIRED (One Time Only) :::\n"\
	"By typing 'I AGREE' you are indicating your agreement to our EULA (https://account.mojang.com"\
	"/documents/minecraft_eula)"
    until [[ $(grep "eula=true" "${eula_file}") ]]; do
	    read -p "[!] Type 'I AGREE' or press CTRL+C to exit: " eula
        if [[ "${eula}" = "I AGREE" ]]; then
        sed -i 's/eula=false/eula=true/g' "${eula_file}"
        fi
    done
}

check_eula() {
	eula_file="${main_dir}/${version}/eula.txt"
	echo -n "[!] Checking if ${eula_file} exists: "
	if [[ -f "${eula_file}" ]]; then
	    echo "OK"
	    echo -n "[!] Checking if eula has been signed: "
	    if [[ $(grep "eula=true" "${eula_file}") ]]; then
	        echo "OK"
	    else
	        if [[ "${pass}" -gt 2 ]]; then
	            err "Eula sign check is looping"
	        fi
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
	    
	    echo "[!] In order to create eula, will startup the server onces (don't worry it 'should' immediately close because of unsigned eula)"
	    echo_and_run --long --exit java -Xms512M -Xmx3G -jar "forge-${version}-${build}.jar" nogui
	    check_eula
	fi
}

server_status() {
	echo -n "[!] Checking for running servers: "
	if server_running_check=$(ps aux &>/dev/stdout| grep -P "java.*\-jar.*\.jar" | grep -ivP "grep.*java" | grep java); then
        echo "FOUND"
        echo -e "----------------\n${server_running_check}"
	    return 0
	else
	    echo -e "NONE FOUND\n${server_running_check}" # Should be an empty variable, but just incase.
	    return 1
	fi
}

server_start() {
    if installed_servers=( $(find ~/minecraft_servers -maxdepth 2 -regex ".*\.jar" | grep -v installer | grep jar) ); then
        echo "[!] Select server to start (Forge = Mods / minecraft_server = Vanilla;no mods)"
    	select run_server_version in "${installed_servers[@]}"; do 
            if [[ "${REPLY}" -gt "${#installed_servers[@]}" ]]; then
                echo "[!] WARN : Please make a proper selection."
            else
                echo "[!] Selected Installed Server: ${run_server_version}"
            fi
	    done
    fi

    echo screen -dmS minecraft_server java -Xms1024m -Xmx3072m -jar ~/minecraft_server/server.jar nogui
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
	    echo_and_run --short --exit ${main_dir}
	fi
  
	server_versions_raw=$(curl -s https://files.minecraftforge.net/maven/net/minecraftforge/forge/index_1.1.html)
	server_versions=( $(<<< "${server_versions_raw}" grep -o "index_.*\.[0-9]\.html"| sed -e 's/index_//g;s/\.html//g') )
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
