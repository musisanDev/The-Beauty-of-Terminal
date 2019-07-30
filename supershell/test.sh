if ! ping -W 2 -c 3 google.com &>/dev/null ; then
    echo "Failed"
else
    echo "OK"
fi
read -p $'Which directory do you want to create as an application directory?\n' APPDIR
: ${APPDIR:="/silis"}
echo $?
