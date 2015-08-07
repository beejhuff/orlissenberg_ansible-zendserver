#!/bin/sh

ZS_VERSION=8.5

usage()
{
cat <<EOF

Usage: $0 <php_version> [nginx] [java] [--automatic] [--repository <url>]
Where php_version is either 5.5 or 5.6.

EOF
return 0
}

LOG_FILE=`mktemp`
if [ -z $LOG_FILE ]; then
	LOG_FILE=/tmp/install_zs.log
fi

SUPPORTED_OS='CentOS|Red Hat Enterprise Linux Server|SUSE|Debian GNU/Linux|Ubuntu|Oracle Linux Server'
echo "Supported OS regex: $SUPPORTED_OS" >> $LOG_FILE


if `which lsb_release > /dev/null 2>&1`; then
	CURRENT_OS=`lsb_release -d -s`
	echo "Current OS detected as: $CURRENT_OS" >> $LOG_FILE
elif [ -f /etc/system-release ]; then
	CURRENT_OS=`head -1 /etc/system-release`
	echo "Current OS detected as: $CURRENT_OS" >> $LOG_FILE
elif [ -f /etc/issue ]; then
	CURRENT_OS=`head -2 /etc/issue`
	echo "Current OS detected as: $CURRENT_OS" >> $LOG_FILE
else
	echo "Can't identify your system using lsb_release or /etc/issue in order to"
	echo "configure Zend's DEB/RPM repositories."
	exit 1
fi
	
# on OEL 5, /etc/issue states "Enterprise Linux Enterprise Linux Server"
UNSUPPORTED_OS='CentOS release 5|Red Hat Enterprise Linux Server release 5|Enterprise Linux Enterprise Linux Server 5|Debian GNU/Linux 6|Ubuntu 10'
echo "Support for the following OS has been stopped: $UNSUPPORTED_OS" >> $LOG_FILE

if ! echo $CURRENT_OS | egrep -q "$SUPPORTED_OS"; then
		echo "Your Linux distribution isn't supported by Zend Server $ZS_VERSION. For a list of supported Linux distributions, "
		echo "see system requirements at http://files.zend.com/help/Zend-Server/zend-server.htm#system_requirements.htm"
		exit 1
elif echo $CURRENT_OS | egrep -q "$UNSUPPORTED_OS" ; then
		echo "Your Linux distribution isn't supported anymore by Zend Server $ZS_VERSION. For a list of supported Linux distributions, "
		echo "see system requirements at http://files.zend.com/help/Zend-Server/zend-server.htm#system_requirements.htm"
		exit 1
fi

# -v or --version
echo "Using `basename $0` version $ZS_VERSION (build: \$Revision: 99634 $)" >> $LOG_FILE
if [ "$1" = "-v" -o "$1" = "--version" ]; then
	echo "`basename $0` version $ZS_VERSION (build: \$Revision: 99634 $)"
	usage
	exit 0
fi

# -h or --help
if [ "$1" = "-h" -o "$1" = "--help" ]; then
	usage
	exit 0
fi

# No parameters
if [ $# -lt 1 ]; then
	usage
	exit 2
fi

# Verify parameter
if [ "$1" != "5.5" -a "$1" != "5.6" ]; then
	usage
	exit 2
else
	PHP=$1
	if [ "$2" = "nginx" ]; then
		shift
		NGINX="nginx"
		WHAT_TO_INSTALL="zend-server-nginx-php-$PHP"
	else
		WHAT_TO_INSTALL="zend-server-php-$PHP"
	fi
	WHAT_TO_INSTALL="$WHAT_TO_INSTALL zend-server-php-$PHP-common"

	if [ "$2" = "java" ]; then
		shift
		WHAT_TO_INSTALL="$WHAT_TO_INSTALL php-$PHP-java-bridge-zend-server"
	fi
	
	echo "Top packages for installation: $WHAT_TO_INSTALL" >> $LOG_FILE
fi

SELINUX_ENABLED_OS='CentOS|Red Hat Enterprise Linux Server|Enterprise Linux Enterprise Linux Server|Oracle Linux Server'

if echo $CURRENT_OS | egrep -q "$SELINUX_ENABLED_OS"; then
	if which getenforce > /dev/null 2> /dev/null && [ `getenforce` = "Enforcing" ]; then
		SELINUX_ENABLED=1;
		echo "SELinux status: `getenforce`." >> $LOG_FILE
	fi
fi

if [ -n "$NGINX" ] && [ "$SELINUX_ENABLED" = "1" ]; then
	echo "Zend Server does not support the installation of Nginx when SELinux is enabled."
	echo "Please either turn off SELinux and retry, or run the Apache installation type."
	exit 2
fi

MYUID=`id -u 2> /dev/null`
if [ ! -z "$MYUID" ]; then
    if [ $MYUID != 0 ]; then
        echo "You need root privileges to run this script.";
        exit 2
    fi
else
    echo "Could not detect UID";
    exit 2
fi

cat <<EOF

Running this script will perform the following:
* Configure your package manager to use Zend Server repository 
* Install Zend Server (PHP $PHP) on your system using your package manager

EOF

if [ "$2" = "--automatic" ]; then
	shift
	if which zypper > /dev/null 2>&1; then
		AUTOMATIC="-n --gpg-auto-import-keys"
	else
		AUTOMATIC="-y"
	fi
else
	AUTOMATIC=""
fi

if [ -z "$AUTOMATIC" ]; then
cat <<EOF
Hit ENTER to install Zend Server (PHP $PHP), or Ctrl+C to abort now.
EOF
# give read a parameter, as it required in dash
read answer
fi

# Upgrade check
UPGRADE=0
echo -n "Tool for checking existing installation: "
if which dpkg 2> /dev/null; then
	INSTALLED_PACKAGES=`dpkg -l '*zend*' | grep ^ii | awk '{print $2}'`
	if `dpkg -l "zend-server*" | grep ^ii | grep -q -E "php-5|cluster-manager"`; then
		UPGRADE=1;
		echo "Will try to upgrade, installed packages detected: $INSTALLED_PACKAGES" >> $LOG_FILE
	else
		INSTALLED_PHP_PACKAGES=`dpkg -l libapache2-mod-php5 | grep ^ii | awk '{print $2}'`;
		echo "Existing PHP packages detected: $INSTALLED_PHP_PACKAGES" >> $LOG_FILE
	fi
elif which rpm 2> /dev/null; then
	INSTALLED_PACKAGES=`rpm -qa --qf="%{NAME}\n" '*zend*'`
	if `rpm -qa | grep "^zend-server" | grep -q -E "php-5|cluster-manager"`; then
		UPGRADE=1;
		echo "Will try to upgrade, installed packages detected: $INSTALLED_PACKAGES" >> $LOG_FILE
	fi
else
	echo
	echo "Your system doesn't support either dpkg or rpm"
	exit 2
fi

# Check if upgrade is allowed
if [ "$UPGRADE" = "1" ]; then
	if [ -f /etc/zce.rc ]; then
		. /etc/zce.rc
	fi

	INSTALLED_PHP=`/usr/local/zend/bin/php -v | head -1 | cut -f2 -d" "`
	INSTALLED_PHP_MAJOR=`echo $INSTALLED_PHP | cut -f1,2 -d"."`

	echo "Found existing installation of Zend Server ($PRODUCT_VERSION) with PHP $INSTALLED_PHP"
	echo "Found existing installation of Zend Server ($PRODUCT_VERSION) with PHP $INSTALLED_PHP" >> $LOG_FILE
	echo

	if [ "$INSTALLED_PHP" = "5.3.15" -o "$INSTALLED_PHP" = "5.4.5" ]; then
		echo "Upgrade from ZendServer 6.0 Beta isn't supported."
		exit 2
	elif [ "$INSTALLED_PHP" = "5.4.0-ZS5.6.0" ]; then
		echo "Upgrade from ZendServer 5.6.0 with PHP 5.4 technology preview isn't supported."
		exit 2
	elif echo "$INSTALLED_PACKAGES" | grep -q cluster-manager; then
		echo "Upgrade from ZendServer cluster manager isn't supported."
		exit 2
	elif [ "$PRODUCT_VERSION" = "5.0.4" -o "$PRODUCT_VERSION" = "5.1.0" -o "$PRODUCT_VERSION" = "5.5.0"  -o "$PRODUCT_VERSION" = "5.6.0" ]; then
		echo "Zend Server does not support a direct upgrade from versions older than Zend Server 6.0."
		echo "Please first upgrade to Zend Server 6.0 before attempting to perform this upgrade again."
		echo "For detailed instructions, please contact our Support team at http://www.zend.com/en/support-center."
		exit 2
	elif [ "$INSTALLED_PHP_MAJOR" = "5.4" -a "$PHP" = "5.3" ]; then
		echo "Downgrade from PHP $INSTALLED_PHP_MAJOR to $PHP isn't supported."
		exit 2
	elif [ "$INSTALLED_PHP_MAJOR" = "5.5" -a "$PHP" = "5.4" ]; then
		echo "Downgrade from PHP $INSTALLED_PHP_MAJOR to $PHP isn't supported."
		exit 2
	elif [ "$INSTALLED_PHP_MAJOR" = "5.5" -a "$PHP" = "5.3" ]; then
		echo "Downgrade from PHP $INSTALLED_PHP_MAJOR to $PHP isn't supported."
		exit 2
	elif echo "$INSTALLED_PACKAGES" | grep -q nginx && [ -z "$NGINX" ]; then
		echo "Zend Server with nginx cannot be upgraded to a different installation type of Zend Server."
		echo "Please uninstall Zend Server and perform a clean installation."
		exit 2
	elif ! (echo "$INSTALLED_PACKAGES" | grep -q nginx) && [ -n "$NGINX" ]; then
		echo "The Zend Server installation type you are currently using cannot be upgraded to Zend Server with nginx."
		echo "Please uninstall Zend Server and perform a clean installation."
		exit 2
	elif echo $CURRENT_OS | egrep -q "Debian GNU/Linux|Ubuntu" && [ "$INSTALLED_PHP_MAJOR" = "5.2" -a "$PHP" = "5.5" ]; then
		echo "The recommend method to upgrade from PHP $INSTALLED_PHP_MAJOR to PHP $PHP is a clean installation. If a clean installation is"
		echo "not an option, you should first upgrade to Zend Server 6.3 with PHP 5.3, and only then upgrade to PHP $PHP."
		exit 2
	fi
else
	if [ -n "$INSTALLED_PHP_PACKAGES" ] && [ -z "$NGINX" ]; then
		echo "Found PHP package $INSTALLED_PHP_PACKAGES from your distribution, please remove it before installing Zend Server"
		exit 2
	fi
fi

# Set nginx.org repository 
if [ "$NGINX" = "nginx" ]; then
	`dirname $0`/nginx/install_nginx.sh
	if [ $? != 0 ]; then
		exit 2
	fi
fi

if [ "$2" = "--repository" ]; then
	if [ -z "$3" ]; then
		echo
		echo "The --repository option requires a URL to install from (HTTP or FTP)."
		exit 2
	else
		REPOSITORY="$3"
		shift
		shift
		echo
		echo "Using $REPOSITORY as the installation source."
		echo "Using $REPOSITORY as the installation source." >> $LOG_FILE
		echo
	fi
else
	REPOSITORY=""
fi

# Set repository 
echo -n "Doing repository configuration for: "
if which apt-get 2> /dev/null; then
	if echo $CURRENT_OS | grep -q -E "Debian GNU/Linux 5|Debian GNU/Linux 6|Ubuntu 10"; then
		REPO_FILE=`dirname $0`/zend.deb.repo
		REPOSITORY_CONTENT="deb $REPOSITORY/deb server non-free"
	elif echo $CURRENT_OS | grep -q -E "Debian GNU/Linux 7|Ubuntu 12|Ubuntu 13.04"; then
		# This is the default for Debian >> 6 and Ubuntu >> 10.04
		REPO_FILE=`dirname $0`/zend.deb_ssl1.0.repo
		REPOSITORY_CONTENT="deb $REPOSITORY/deb_ssl1.0 server non-free"
	else
		# This is the default for Debian >> 7 and Ubuntu >> 13.04
		if [ `uname -m` = "ppc64le" ]; then
			REPO_FILE=`dirname $0`/zend.deb_power8.repo
			REPOSITORY_CONTENT="deb $REPOSITORY/deb_power8 server non-free"
		else
			REPO_FILE=`dirname $0`/zend.deb_apache2.4.repo
			REPOSITORY_CONTENT="deb $REPOSITORY/deb_apache2.4 server non-free"
		fi
	fi

	TARGET_REPO_FILE=/etc/apt/sources.list.d/zend.list
	SYNC_COMM="apt-get update"
	wget http://repos.zend.com/zend.key -O- 2> /dev/null | apt-key add -
elif which zypper 2> /dev/null; then
	REPO_FILE=`dirname $0`/zend.rpm.suse.repo
	read -r -d '' REPOSITORY_CONTENT <<-'EOF'
		[Zend]
		name=Zend Server
		baseurl=$REPOSITORY/sles/\$basearch
		type=rpm-md
		enabled=1
		autorefresh=1
		gpgcheck=1
		gpgkey=http://repos.zend.com/zend.key

		[Zend_noarch]
		name=Zend Server - noarch
		baseurl=$REPOSITORY/sles/noarch
		type=rpm-md
		enabled=1
		autorefresh=1
		gpgcheck=1
		gpgkey=http://repos.zend.com/zend.key
	EOF
	TARGET_REPO_FILE=/etc/zypp/repos.d/zend.repo
	if [ "$UPGRADE" = "1" ]; then
		SYNC_COMM="zypper clean -a"
	fi

	mkdir -p /etc/zypp/repos.d

	# Change arch in the repo file 
	if [ "`uname -m`" == "x86_64" ]; then
		ARCH=x86_64;
	elif [ "`uname -m`" == "i686" ]; then
		ARCH=i586;
	fi
	SYNC_COMM="sed -i \"s/\\\$basearch/$ARCH/g\" ${TARGET_REPO_FILE}; $SYNC_COMM"
elif which yum 2> /dev/null; then
	if echo $CURRENT_OS | grep -q -E "CentOS release 6|Red Hat Enterprise Linux Server release 6|Oracle Linux Server release 6"; then
		# RHEL / Centos 6
		REPO_FILE=`dirname $0`/zend.rpm.repo
		read -r -d '' REPOSITORY_CONTENT <<-'EOF'
			[Zend]
			name=Zend Server
			baseurl=$REPOSITORY/rpm/\$basearch
			enabled=1
			gpgcheck=1
			gpgkey=http://repos.zend.com/zend.key

			[Zend_noarch]
			name=Zend Server - noarch
			baseurl=$REPOSITORY/rpm/noarch
			enabled=1
			gpgcheck=1
			gpgkey=http://repos.zend.com/zend.key
		EOF
	elif echo $CURRENT_OS | grep -q -E "CentOS Linux release 7|Red Hat Enterprise Linux Server release 7|Oracle Linux Server release 7"; then
		# RHEL / Centos 7
		REPO_FILE=`dirname $0`/zend.rpm_apache2.4.repo
		read -r -d '' REPOSITORY_CONTENT <<-'EOF'
			[Zend]
			name=Zend Server
			baseurl=$REPOSITORY/rpm_apache2.4/\$basearch
			enabled=1
			gpgcheck=1
			gpgkey=http://repos.zend.com/zend.key

			[Zend_noarch]
			name=Zend Server - noarch
			baseurl=$REPOSITORY/rpm_apache2.4/noarch
			enabled=1
			gpgcheck=1
			gpgkey=http://repos.zend.com/zend.key
		EOF
	fi
	TARGET_REPO_FILE=/etc/yum.repos.d/zend.repo
	if [ "$UPGRADE" = "1" ]; then
		SYNC_COMM="$SYNC_COMM yum clean all"
	fi
else
	echo
	echo "Can't determine which repository should be setup (apt-get, yum or zypper)"
	exit 2
fi

if [ -n "$REPOSITORY" ]; then
	echo "$REPOSITORY_CONTENT" > $TARGET_REPO_FILE
	REPOSITORY_RC=$?
else
	cp $REPO_FILE $TARGET_REPO_FILE
	REPOSITORY_RC=$?
fi

if [ $REPOSITORY_RC != 0 ]; then
	echo
	echo "***************************************************************************************"
	echo "* Zend Server Installation was not completed. Can't setup package manager repository. *" 
	echo "***************************************************************************************"
	exit 2
else
	echo "Repository was set at $TARGET_REPO_FILE" >> $LOG_FILE
fi

if [ -n "$SYNC_COMM" ]; then
	eval $SYNC_COMM
fi

RC=0


# Clean Installation
if [ "$UPGRADE" = "0" ]; then
	echo "Clean installation" >> $LOG_FILE
	echo -n "Package manager for installation: "
	if which aptitude 2> /dev/null; then
		echo "Executing: aptitude $AUTOMATIC install $WHAT_TO_INSTALL" >> $LOG_FILE
		aptitude $AUTOMATIC install $WHAT_TO_INSTALL
		RC=$?
		echo "Exit code: $RC" >> $LOG_FILE
		dpkg-query -W -f='${Status}\n' $WHAT_TO_INSTALL | grep -q ' installed'
		VERIFY_RC=$?
	elif which apt-get 2> /dev/null; then
		echo "Executing: apt-get $AUTOMATIC install $WHAT_TO_INSTALL" >> $LOG_FILE
		apt-get $AUTOMATIC install $WHAT_TO_INSTALL
		RC=$?
		echo "Exit code: $RC" >> $LOG_FILE
		dpkg-query -W -f='${Status}\n' $WHAT_TO_INSTALL | grep -q ' installed'
		VERIFY_RC=$?
	elif which yum 2> /dev/null; then
		echo "Executing: yum $AUTOMATIC install $WHAT_TO_INSTALL" >> $LOG_FILE
		yum $AUTOMATIC install $WHAT_TO_INSTALL
		RC=$?
		echo "Exit code: $RC" >> $LOG_FILE
		rpm -q --qf "%{name} %{version}\n" $WHAT_TO_INSTALL 2> /dev/null
		VERIFY_RC=$?
	elif which zypper 2> /dev/null; then
		echo "Executing: zypper $AUTOMATIC install $WHAT_TO_INSTALL" >> $LOG_FILE
		zypper $AUTOMATIC install $WHAT_TO_INSTALL
		RC=$?
		echo "Exit code: $RC" >> $LOG_FILE
		rpm -q --qf "%{name} %{version}\n" $WHAT_TO_INSTALL 2> /dev/null
		VERIFY_RC=$?
	else
		echo
		echo "Can't determine which package manager (aptitude, apt-get, yum or zypper) should be used for installation of $WHAT_TO_INSTALL"
		exit 2
	fi
fi

# Upgrade
if [ "$UPGRADE" = "1" ]; then
	if [ -f /etc/zce.rc ]; then
		. /etc/zce.rc
	fi

	# Backup etc
	BACKUP_SUFFIX=$PRODUCT_VERSION
	
	if [ ! -d $ZCE_PREFIX/etc-$BACKUP_SUFFIX ]; then
		mkdir $ZCE_PREFIX/etc-$BACKUP_SUFFIX
	fi

	# Remove possible leftovers from previous upgrade (ZSRV-12019)
	if [ -f $ZCE_PREFIX/etc/php.ini.rpmsave ]; then
		mv -f $ZCE_PREFIX/etc/php.ini.rpmsave $ZCE_PREFIX/etc/php.ini.rpmsave.old
	fi

	cp -rp $ZCE_PREFIX/etc/* $ZCE_PREFIX/etc-$BACKUP_SUFFIX/

	if [ ! -d $ZCE_PREFIX/lighttpd-etc-$BACKUP_SUFFIX ]; then
		mkdir $ZCE_PREFIX/lighttpd-etc-$BACKUP_SUFFIX
	fi

	cp -rp $ZCE_PREFIX/gui/lighttpd/etc/* $ZCE_PREFIX/lighttpd-etc-$BACKUP_SUFFIX/

	# Workaround an upgrade bug in our 6.1.0 Debian packages (ZSRV-11344)
	if [ "$BACKUP_SUFFIX" = "6.1.0" -o "$BACKUP_SUFFIX" = "6.2.0" ]; then
		if which dpkg 2> /dev/null; then
			mkdir -p $ZCE_PREFIX/etc-$BACKUP_SUFFIX-workaround
			cp -rp $ZCE_PREFIX/etc/* $ZCE_PREFIX/etc-$BACKUP_SUFFIX-workaround
		fi
	fi

	echo -n "Package manager for upgrade: "
	if [ "$INSTALLED_PHP_MAJOR" = "$PHP" ]; then
		echo "Same PHP upgrade" >> $LOG_FILE
		# Same PHP upgrade
		if which aptitude 2> /dev/null; then
			echo "Executing: aptitude $AUTOMATIC install '~izend'" >> $LOG_FILE
			aptitude $AUTOMATIC install '~izend'
			RC=$?
			echo "Exit code: $RC" >> $LOG_FILE
			dpkg-query -W -f='${Status}\n' $WHAT_TO_INSTALL | grep -q ' installed'
			VERIFY_RC=$?
		elif which apt-get 2> /dev/null; then
			echo "Executing: apt-get $AUTOMATIC install $WHAT_TO_INSTALL" >> $LOG_FILE
			apt-get $AUTOMATIC install $WHAT_TO_INSTALL
			RC=$?
			echo "Exit code: $RC" >> $LOG_FILE
			dpkg-query -W -f='${Status}\n' $WHAT_TO_INSTALL | grep -q ' installed'
			VERIFY_RC=$?
			apt-get $AUTOMATIC install `dpkg -l '*zend*' | grep ^ii | awk '{print $2}'`
		elif which yum 2> /dev/null; then
			echo "Executing: yum $AUTOMATIC upgrade '*zend*'" >> $LOG_FILE
			yum $AUTOMATIC upgrade '*zend*'
			RC=$?
			echo "Exit code: $RC" >> $LOG_FILE
			rpm -q --qf "%{name} %{version}\n" $WHAT_TO_INSTALL 2> /dev/null
			VERIFY_RC=$?
		elif which zypper 2> /dev/null; then
			echo "Executing: zypper $AUTOMATIC update -r Zend -r Zend_noarch" >> $LOG_FILE
			zypper $AUTOMATIC update -r Zend -r Zend_noarch
			RC=$?
			echo "Exit code: $RC" >> $LOG_FILE
			echo "Executing: zypper $AUTOMATIC install $WHAT_TO_INSTALL" >> $LOG_FILE
			zypper $AUTOMATIC install $WHAT_TO_INSTALL
			rpm -q --qf "%{name} %{version}\n" $WHAT_TO_INSTALL 2> /dev/null
			VERIFY_RC=$?
		else
			echo
			echo "Can't determine which package manager (aptitude, apt-get, yum or zypper) should be used for upgrade to $WHAT_TO_INSTALL"
			exit 2
		fi
	else
		# PHP upgrade
		echo "PHP upgrade" >> $LOG_FILE

		EXTRA_PACKAGES="zend-server-framework-dojo zend-server-framework-extras source-zend-server pdo-informix-zend-server pdo-ibm-zend-server ibmdb2-zend-server java-bridge-zend-server \-javamw-zend-server"
		WHAT_TO_INSTALL_EXTRA=""

		# Find which extra packages we have and should be installed
		for package in $EXTRA_PACKAGES; do 
			EXTRA_PACKAGE=`echo "$INSTALLED_PACKAGES" | grep $package | sed "s/$INSTALLED_PHP_MAJOR/$PHP/g"`
			if [ -n "$EXTRA_PACKAGE" ]; then
				WHAT_TO_INSTALL_EXTRA="$WHAT_TO_INSTALL_EXTRA $EXTRA_PACKAGE"
			fi
		done

		if which apt-get 2> /dev/null; then
			if ! echo $CURRENT_OS | grep -q -E "Debian GNU/Linux 5|Debian GNU/Linux 6|Ubuntu 10|Ubuntu 12.04"; then
				# Remove the zend-server package when apt-get version newer than 0.8
				apt-get $AUTOMATIC remove `echo $WHAT_TO_INSTALL | sed "s/$PHP/$INSTALLED_PHP_MAJOR/g"`
			fi
			echo "Executing: apt-get $AUTOMATIC install $WHAT_TO_INSTALL $WHAT_TO_INSTALL_EXTRA" >> $LOG_FILE
			apt-get $AUTOMATIC install $WHAT_TO_INSTALL $WHAT_TO_INSTALL_EXTRA
			RC=$?
			echo "Exit code: $RC" >> $LOG_FILE
			if [ $RC -eq 0 ]; then
				apt-get $AUTOMATIC install `dpkg -l '*zend*' | grep ^ii | awk '{print $2}'`
			fi
			dpkg-query -W -f='${Package} ${Version}\n' $WHAT_TO_INSTALL 2> /dev/null
			VERIFY_RC=$?
		elif which yum 2> /dev/null; then
			yum $AUTOMATIC remove "zend-server*-php-5.*" && yum $AUTOMATIC remove "deployment-daemon-zend-server" && yum $AUTOMATIC remove "*zend*"
			echo "Executing: yum $AUTOMATIC install $WHAT_TO_INSTALL $WHAT_TO_INSTALL_EXTRA" >> $LOG_FILE
			yum $AUTOMATIC install $WHAT_TO_INSTALL $WHAT_TO_INSTALL_EXTRA
			RC=$?
			echo "Exit code: $RC" >> $LOG_FILE
			rpm -q --qf "%{name} %{version}\n" $WHAT_TO_INSTALL 2> /dev/null
			VERIFY_RC=$?
		elif which zypper 2> /dev/null; then
			echo "Using zypper for upgrade" >> $LOG_FILE
			zypper $AUTOMATIC remove "zend-server*-php-5.*" && zypper $AUTOMATIC remove "deployment-daemon-zend-server" && zypper $AUTOMATIC remove "*zend*"
			echo "Executing: zypper $AUTOMATIC install $WHAT_TO_INSTALL $WHAT_TO_INSTALL_EXTRA" >> $LOG_FILE
			zypper $AUTOMATIC install $WHAT_TO_INSTALL $WHAT_TO_INSTALL_EXTRA
			RC=$?
			echo "Exit code: $RC" >> $LOG_FILE
			rpm -q --qf "%{name} %{version}\n" $WHAT_TO_INSTALL 2> /dev/null
			VERIFY_RC=$?
		else
			echo
			echo "Can't determine which package manager (aptitude, apt-get, yum or zypper) should be used for upgrade to $WHAT_TO_INSTALL"
			exit 2
		fi
	fi
fi

if [ $RC -eq 0 -a $VERIFY_RC -eq 0 ]; then
	# Restart ZendServer on RHEL and friends when SELinux is enabled
	if [ "$SELINUX_ENABLED" = "1" ]; then
		echo "Active SELinux detected, updating rules" >> $LOG_FILE

		echo
		echo "SELinux detcted, restarting ZendServer to apply SELinux settings."
		echo "See http://files.zend.com/help/Zend-Server/zend-server.htm#selinux.htm for more information"

		if [ "$UPGRADE" = "1" -a "$PRODUCT_VERSION" = "5.6.0" ]; then
			# Cluster upgrade on 5.6 takes longer, wait with the restart
			sleep 60;
		fi

		/usr/local/zend/bin/zendctl.sh restart
	fi

	echo
	echo "***********************************************************"
	echo "* Zend Server was successfully installed. 		*"
	echo "* 							*"
	echo "* To access the Zend Server UI open your browser at:	*"
	echo "* https://<hostname>:10082/ZendServer (secure) 		*" 
	echo "* or 							*" 
	echo "* http://<hostname>:10081/ZendServer			*" 
	echo "***********************************************************"
else
	echo
	echo "************************************************************************************************"
	echo "* Zend Server Installation was not completed. See output above for detailed error information. *" 
	echo "************************************************************************************************"
fi
echo

mv -f $LOG_FILE /tmp/install_zs.log.$$
echo "Log file is kept at /tmp/install_zs.log.$$"

if [ $VERIFY_RC -ne 0 ]; then
	exit $VERIFY_RC
else
	exit $RC
fi
