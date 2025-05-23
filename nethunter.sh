#!/data/data/com.termux/files/usr/bin/bash -e

VERSION=2020011601
BASE_URL=https://kali.download/nethunter-images/current/rootfs
USERNAME=jefdansil

function unsupported_arch() {
    printf "${red}"
    echo "[*] Arquitetura não suportada \n\n"
    printf "${reset}"
    exit
}

function ask() {
    # http://djm.me/ask
    while true; do

        if [ "${2:-}" = "Y" ]; then
            prompt="Y"
            default=Y
        elif [ "${2:-}" = "Y" ]; then
            prompt="y"
            default=Y
        else
            prompt="y/n"
            default=
        fi

        # Faça a pergunta
        printf "${light_cyan}\n[?] "
        read -p "$1 [$prompt] " REPLY

        # Default?
        if [ -z "$REPLY" ]; then
            REPLY=$default
        fi

        printf "${reset}"

        # Check if the reply is valid
        case "$REPLY" in
            Y*|y*) return 0 ;;
            Y*|y*) return 1 ;;
        esac
    done
}

function get_arch() {
    printf "${blue}[*] Verificando a arquitetura do dispositivo ..."
    case $(getprop ro.product.cpu.abi) in
        arm64-v8a)
            SYS_ARCH=arm64
            ;;
        armeabi|armeabi-v7a)
            SYS_ARCH=armhf
            ;;
        *)
            unsupported_arch
            ;;
    esac
}

function set_strings() {
    CHROOT=kali-${SYS_ARCH}
    IMAGE_NAME=kalifs-${SYS_ARCH}-full.tar.xz
    SHA_NAME=kalifs-${SYS_ARCH}-full.sha512sum
}    

function prepare_fs() {
    unset KEEP_CHROOT
    if [ -d ${CHROOT} ]; then
        if ask "Diretório rootfs existente encontrado. Excluir e criar um novo?" "N"; then
            rm -rf ${CHROOT}
        else
            KEEP_CHROOT=1
        fi
    fi
} 

function cleanup() {
    if [ -f ${IMAGE_NAME} ]; then
        if ask "Excluir arquivo rootfs baixado?" "N"; then
	    if [ -f ${IMAGE_NAME} ]; then
                rm -f ${IMAGE_NAME}
	    fi
	    if [ -f ${SHA_NAME} ]; then
                rm -f ${SHA_NAME}
	    fi
        fi
    fi
} 

function check_dependencies() {
    printf "${blue}\n[*] Verificando as dependências do pacotes...${reset}\n"
    ## Workaround for termux-app issue #1283 (https://github.com/termux/termux-app/issues/1283)
    ##apt update -y &> /dev/null
    apt-get update -y &> /dev/null || apt-get -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confnew" dist-upgrade -y &> /dev/null

    for i in proot tar axel; do
        if [ -e $PREFIX/bin/$i ]; then
            echo "  $i is OK"
        else
            printf "Installing ${i}...\n"
            apt install -y $i || {
                printf "${red}ERROR: Falha ao instalar pacotes.\n Exiting.\n${reset}"
	        exit
            }
        fi
    done
    apt upgrade -y
}


function get_url() {
    ROOTFS_URL="${BASE_URL}/${IMAGE_NAME}"
    SHA_URL="${BASE_URL}/${SHA_NAME}"
}

function get_rootfs() {https://kali.download/nethunter-images/current/rootfs/kali-nethunter-rootfs-full-arm64.tar.xz}
    unset KEEP_IMAGE
    if [ -f ${IMAGE_NAME} ]; then
        if ask "Arquivo de imagem existente encontrado. Excluir e baixar um novo?" "N"; then
            rm -f ${IMAGE_NAME}
        else
            printf "${yellow}[!] Usando o arquivo rootfs existente${reset}\n"
            KEEP_IMAGE=1
            return
        fi
    fi
    printf "${blue}[*] Baixando rootfs...${reset}\n\n"
    get_url
    wget ${EXTRA_ARGS} --continue "${ROOTFS_URL}"
}

function get_sha() {
    if [ -z $KEEP_IMAGE ]; then
        printf "\n${blue}[*] Getting SHA ... ${reset}\n\n"
        get_url
        if [ -f ${SHA_NAME} ]; then
            rm -f ${SHA_NAME}
        fi
        wget ${EXTRA_ARGS} --continue "${SHA_URL}"
    fi
}

function verify_sha() {
    if [ -z $KEEP_IMAGE ]; then
        printf "\n${blue}[*] Verifying integrity of rootfs...${reset}\n\n"
        sha512sum -c $SHA_NAME || {
            printf "${red} Rootfs corrompidos. Execute este instalador novamente ou baixe o arquivo manualmente\n${reset}"
            exit 1
        }
    fi
}

function extract_rootfs() {
    if [ -z $KEEP_CHROOT ]; then
        printf "\n${blue}[*] Extraindo rootfs... ${reset}\n\n"
        proot --link2symlink tar -xf $IMAGE_NAME 2> /dev/null || :
    else        
        printf "${yellow}[!] Usando o diretório rootfs existente${reset}\n"
    fi
}


function create_launcher() {
    KALI_LAUNCHER=${PREFIX}/bin/nethunter
    KALI_SHORTCUT=${PREFIX}/bin/KALI
    cat > $KALI_LAUNCHER <<- EOF
#!/data/data/com.termux/files/usr/bin/bash -e
cd \${HOME}
## termux-exec sets LD_PRELOAD so let's unset it before continuing
unset LD_PRELOAD
## Workaround for Libreoffice, also needs to bind a fake /proc/version
if [ ! -f $CHROOT/root/.version ]; then
    touch $CHROOT/root/.version
fi

## Default user is "kali"
user="$USERNAME"
home="/home/\$user"
start="sudo -u kali /bin/bash"

## NH can be launched as root with the "-r" cmd attribute
## Also check if user kali exists, if not start as root
if grep -q "kali" ${CHROOT}/etc/passwd; then
    KALIUSR="1";
else
    KALIUSR="0";
fi
if [[ \$KALIUSR == "0" || ("\$#" != "0" && ("\$1" == "-r" || "\$1" == "-R")) ]];then
    user="root"
    home="/\$user"
    start="/bin/bash --login"
    if [[ "\$#" != "0" && ("\$1" == "-r" || "\$1" == "-R") ]];then
        shift
    fi
fi

cmdline="proot \\
        --link2symlink \\
        -0 \\
        -r $CHROOT \\
        -b /dev \\
        -b /proc \\
        -b $CHROOT\$home:/dev/shm \\
        -w \$home \\
           /usr/bin/env -i \\
           HOME=\$home \\
           PATH=/usr/local/sbin:/usr/local/bin:/bin:/usr/bin:/sbin:/usr/sbin \\
           TERM=\$TERM \\
           LANG=C.UTF-8 \\
           \$start"

cmd="\$@"
if [ "\$#" == "0" ];then
    exec \$cmdline
else
    \$cmdline -c "\$cmd"
fi
EOF

    chmod 700 $KALI_LAUNCHER
    if [ -L ${KALI_SHORTCUT} ]; then
        rm -f ${KALI_SHORTCUT}
    fi
    if [ ! -f ${KALI_SHORTCUT} ]; then
        ln -s ${KALI_LAUNCHER} ${KALI_SHORTCUT} >/dev/null
    fi
   
}

function create_kex_launcher() {
    KEX_LAUNCHER=${CHROOT}/usr/bin/kex
    cat > $KEX_LAUNCHER <<- EOF
#!/bin/bash

function start-kex() {
    if [ ! -f ~/.vnc/passwd ]; then
        passwd-kex
    fi
    USR=\$(whoami)
    if [ \$USR == "root" ]; then
        SCREEN=":2"
    else
        SCREEN=":1"
    fi 
    export HOME=\${HOME}; export USER=\${USR}; LD_PRELOAD=/usr/lib/aarch64-linux-gnu/libgcc_s.so.1 nohup vncserver \$SCREEN >/dev/null 2>&1 </dev/null
    starting_kex=1
    return 0
}

function stop-kex() {
    vncserver -kill :1 | sed s/"Xtigervnc"/"NetHunter KeX"/
    vncserver -kill :2 | sed s/"Xtigervnc"/"NetHunter KeX"/
    return $?
}

function passwd-kex() {
    vncpasswd
    return $?
}

function status-kex() {
    sessions=\$(vncserver -list | sed s/"TigerVNC"/"NetHunter KeX"/)
    if [[ \$sessions == *"590"* ]]; then
        printf "\n\${sessions}\n"
        printf "\nYou can use the KeX client to connect to any of these displays.\n\n"
    else
        if [ ! -z \$starting_kex ]; then
            printf '\nError starting the KeX server.\nPlease try "nethunter kex kill" or restart your termux session and try again.\n\n'
        fi
    fi
    return 0
}

function kill-kex() {
    pkill Xtigervnc
    return \$?
}

case \$1 in
    start)
        start-kex
        ;;
    stop)
        stop-kex
        ;;
    status)
        status-kex
        ;;
    passwd)
        passwd-kex
        ;;
    kill)
        kill-kex
        ;;
    *)
        stop-kex
        start-kex
        status-kex
        ;;
esac
EOF

    chmod 700 $KEX_LAUNCHER
}

function fix_profile_bash() {
    ## Impedir a tentativa de criar links no sistema de arquivos somente leitura
    if [ -f ${CHROOT}/root/.bash_profile ]; then
        sed -i '/if/,/fi/d' "${CHROOT}/root/.bash_profile"
    fi
}

function fix_sudo() {
    ## corrigir sudo e su ao iniciar
    chmod +s $CHROOT/usr/bin/sudo
    chmod +s $CHROOT/usr/bin/su
	echo "kali    ALL=(ALL:ALL) ALL" > $CHROOT/etc/sudoers.d/kali

    # https://bugzilla.redhat.com/show_bug.cgi?id=1773148
    echo "Set disable_coredump false" > $CHROOT/etc/sudo.conf
}

function fix_uid() {
    ## Altere kali uid e gid para corresponder ao do usuário termux
    USRID=$(id -u)
    GRPID=$(id -g)
    nh -r usermod -u $USRID kali 2>/dev/null
    nh -r groupmod -g $GRPID kali 2>/dev/null
}

function print_banner() {
    clear
    printf "${yellow}##################################################\n"
    printf "${blue}##                                              ##\n"
    printf "${green}##  88      a8P         db        88        88  ##\n"
    printf "${green}##  88    .88'         d88b       88        88  ##\n"
    printf "${green}##  88   88'          d8''8b      88        88  ##\n"
    printf "${green}##  88 d88           d8'  '8b     88        88  ##\n"
    printf "${green}##  8888'88.        d8YaaaaY8b    88        88  ##\n"
    printf "${green}##  88P   Y8b      d8''''''''8b   88        88  ##\n"
    printf "${green}##  88     '88.   d8'        '8b  88        88  ##\n"
    printf "${green}##  88       Y8b d8'          '8b 888888888 88  ##\n"
    printf "${green}##                                              ##\n"
    printf "${grenn}################# Gilmar Filho#####################${reset}\n\n"
}


##################################
##              Main            ##

# Adicione algumas coresred='\033[1;31m'
green='\033[1;32m'
yellow='\033[1;33m'
blue='\033[1;34m'
light_cyan='\033[1;96m'
reset='\033[0m'

EXTRA_ARGS=""
if [[ ! -z $1 ]]; then
    EXTRA_ARGS=$1
    if [[ $EXTRA_ARGS != "--no-check-certificate" ]]; then
        EXTRA_ARGS=""
    fi
fi

cd $HOME
print_banner
get_arch
set_strings
prepare_fs
check_dependencies
get_rootfs
get_sha
verify_sha
extract_rootfs
create_launcher
cleanup

printf "\n${blue}[*] Configurando Kali Termux ...\n"
fix_profile_bash
fix_sudo
create_kex_launcher
fix_uid

print_banner
printf "${green}[=] Kali no  Termux instalado com sucesso${reset}\n\n"
printf "${green}[+] DIGITE KALLI , type:${reset}\n"

sleep 6s
echo Limpando a tela em 6 segundos

sleep 6s

cls

clear

KALI
