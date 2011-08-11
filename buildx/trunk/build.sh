#!/bin/bash
#
# Headless building script 
#
# Used environment variables 
# 
# $WORKSPACE	: root path containing all build artifacts 
# $OSNAME	: the target platform name i.e. linux, macosx, windows		
# $OSARCH	: the target platform architecture i.e. i386, x64
# $BUILD_REPO   : (optional) shared path to cache thirdy parts tools compiled binaries
# $SVN_REVISION : (optional) the svn revision used to mark this buld
# $VERSION 	: (optional) the version used to tag this build
# $BUILD_REPO	: (optional) the path where compiled binaries will be cached
# $USER_BIN	: (deprecated) path where store binary to be used 
#
# Required dependencies: 
# - wget 
# - antiword
# - installbuild (http://installbuilder.bitrock.com)
#

#
# Release flag  
# 
if [ -z $RELEASE ]; then 
export RELEASE=0
fi

#
# default SVN revision number 
#
if [ -z $SVN_REVISION ]; then 
SVN_REVISION=`svn info http://tcoffee.googlecode.com/svn/tcoffee/trunk | grep "Last Changed Rev:" | awk '{ print $4 }'`
fi

if [ $SVN_REVISION == "" ]; then 
  echo 'Missing $SVN_REVISION value. Cannot continue the build process.' 
  exit 1
fi

if [[ (-z $VERSION) || ($VERSION == auto) ]]; then 
	if [ $RELEASE == 1 ]; then 
	export VERSION=`cat $WORKSPACE/tcoffee/t_coffee/src/version_number.version`
	else 
	export VERSION=r$SVN_REVISION
	fi
fi

#
# The date timestamp string contains also the svn revision number
#
if [ -z $DATE ]; then 
export DATE="`date +"%Y-%m-%d %H:%M:%S"` - Revision $SVN_REVISION"
fi

# default bin path 
if [ -z $USER_BIN ]; then 
export USER_BIN=$WORKSPACE/bin/
fi

#
# default third party binaries cache location 
#
if [ -z $BUILD_REPO ]; then 
export BUILD_REPO=$WORKSPACE/repo
fi

#
# default install builder location 
#
if [ -z $INSTALLER ]; then 
	INSTALLER=~/installbuilder-7.2.0/bin/builder
	if [ $OSNAME == "macosx" ]
	then
	INSTALLER=~/InstallBuilder-7.2.0/bin/Builder.app/Contents/MacOS/installbuilder.sh
	fi
fi

# Flag DO_TEST, if true test are executed (default: true)
if [ -z $DO_TEST ]; then 
DO_TEST=1
fi 

#
# script directives
#

set -e
set -u
set -o nounset
set -o errexit
#set -x

#
# other common variables 
#
SANDBOX=$WORKSPACE/sandbox
PERLM=$WORKSPACE/perl

_SRC=$WORKSPACE/tcoffee/t_coffee/src
_G_USR=cbcrg.lab
_G_PWD=Zf4Na7vf8SX8

#
# Define the distribution directory that will contain produced artifacts
#
DIST_ROOT=$SANDBOX/distributions

if [ $RELEASE == 1 ]; then
DIST_BASE=$SANDBOX/distributions/Stable/
else
DIST_BASE=$SANDBOX/distributions/Beta/
fi

# Distribution package file name
DIST_DIR=$DIST_BASE/$VERSION/$OSNAME
DIST_NAME=T-COFFEE_distribution_$VERSION.tar.gz
DIST_HOST='tcoffeeo@tcoffee.org:~/public_html/Packages/'

# Installer package file name 
INST_NAME=T-COFFEE_installer_$VERSION\_$OSNAME\_$OSARCH

SERVER_NAME=T-COFFEE_server_$VERSION\_$OSNAME\_$OSARCH
SERVER_DIR=$SANDBOX/server/$SERVER_NAME
SERVER_WAR=$SANDBOX/war
UNTARED=$SANDBOX/untared_distributions/T-COFFEE_distribution_$VERSION
TCDIR=$SANDBOX/untared_binaries

#
# exported variabled
#
export HOME2=$SANDBOX


#
# Display the current environment
#
function env() 
{
  echo "[ env ]"

  echo "- WORKSPACE   : $WORKSPACE"
  echo "- OSNAME      : $OSNAME"
  echo "- OSARCH      : $OSARCH"
  echo "- VERSION     : $VERSION"
  echo "- DATE        : $DATE"
  echo "- RELEASE     : $RELEASE"
  echo "- BUILD_REPO  : $BUILD_REPO"
  echo "- SVN_REVISION: $SVN_REVISION"
  echo "- USER_BIN    : $USER_BIN"
  echo ". SANDBOX     : $SANDBOX"
  echo ". _SRC        : $_SRC"
  echo ". SERVER_NAME : $SERVER_NAME" 
  echo ". SERVER_DIR  : $SERVER_DIR"
  echo ". SERVER_WAR  : $SERVER_WAR"
  echo ". UNTARED     : $UNTARED"  
  echo ". INSTALLER   : $INSTALLER"
  echo ". TCDIR       : $TCDIR"
  echo ". PERLM       : $PERLM"
  echo ". DIST_BASE   : $DIST_BASE"
  echo ". DIST_DIR    : $DIST_DIR"
  echo ". DIST_NAME   : $DIST_NAME"
  echo ". DIST_HOST   : $DIST_HOST"
  echo ". INST_NAME   : $INST_NAME"
  echo ". DO_TEST     : $DO_TEST"

}

#
# clean current sandbox content 
#
function clean() 
{
	echo "[ clean ]"
	rm -rf $SANDBOX

}

#
# Execute legacy doc_test target 
#
function doc_test() { 
	echo "[ doc_test ]"

	# remove previous result (if any)
	rm -rf $WORKSPACE/test-results
	
	# run tests 
	cd $WORKSPACE/tcoffee/testsuite/
	
	set +e
	java -jar black-coffee.jar --var tcoffee.home=$TCDIR --stop=failed --print-stdout=never --print-stderr=never --sandbox-dir=$WORKSPACE/test-results  ./documentation/ | tee $WORKSPACE/test.log

	if [ $? != 0 ]; then
		echo "Some test FAILED. Check result file: $WORKSPACE/test.log "
		exit 2
	fi

	#check that the result test file exists
	if [ ! -f $WORKSPACE/test.log ] 
	then 
		echo "test.log result file is missing."
		exit 2
	fi	 

	if [ $? == 0 ]; then
		echo "All tests PASSED. Check result file: $WORKSPACE/test.log "
	fi
	set -e	
}


#
# rename temporary makefile and run it
#
function build_dist() 
{
	echo "[ build_dist ]"
	cd $_SRC
	make distribution || true

	# check that the distribution file has been  created
	DIST_FILE=$SANDBOX/distributions/$DIST_NAME
	if [ ! -f $DIST_FILE ] 
	then 
		echo "Destination file has not been created: $DIST_FILE"
		exit 1
	fi

	# Move created package to distribution directory define by $DIST_DIR
	mkdir -p $DIST_BASE/$VERSION
	mv $DIST_FILE $DIST_BASE/$VERSION
	
	# Create a file containing the latest version number 
	echo $VERSION > $DIST_BASE/.version

}

#
# Upload all packages 
#
function upload() 
{
	echo "[ upload_distribution ]"

	scp -B -2 -r -i $WORKSPACE/build/tcoffee_org_id $DIST_BASE $DIST_HOST
}


#
# Compile T-Coffee distribution
# - distribution sources are located at $UNTARED path
# - target binaries will be located at $TCDIR 
#
function build_binaries()
{
	echo "[ build_binaries ]"

	rm -rf $TCDIR
	mkdir -p $TCDIR
	mkdir -p $TCDIR/bin

	# create t-coffee binaries installation
	cd $UNTARED
	./install all -tclinkdb=./tclinkdb.txt -repo=$BUILD_REPO -tcdir=$TCDIR -exec=$TCDIR/bin || true
    
    # Check that the binary has successfully compiled 
	if [ ! -f $TCDIR/bin/t_coffee ] 
	then 
		echo "Target 't_coffee' binary has not been compiled"
		exit 1
	fi    
    
    
	# add perl modules 
	cp -r $PERLM/lib/perl5/ $TCDIR/perl
	
	# add gfortran libraries
	if [ $OSNAME == "macosx" ] 
	then 
		mkdir -p $TCDIR/gfortran
		cp /usr/local/lib/libgfortran.3.dylib $TCDIR/gfortran
		cp /usr/local/lib/libgfortran.a $TCDIR/gfortran
		cp /usr/local/lib/libgfortran.la $TCDIR/gfortran
	fi
}



#
# Run all tests and publish result to workspace
#
# Depends on: pack_server
#  
#function test_server() 
#{
#	echo "[ test_server ]"
#
# 	# clean required directories
#	rm -rf $SANDBOX/web
#	rm -rf $SANDBOX/$SERVER_NAME 
#	mkdir -p $SANDBOX/$SERVER_NAME
#
#	# unzip the distribution file
#	unzip $DIST_DIR/$SERVER_NAME.zip -d $SANDBOX > /dev/null
#	mv $SANDBOX/$SERVER_NAME $SANDBOX/web
#
#	# kill tcoffee test server instance if ANY
#	kill -9 `ps -ef  | grep 'play test' | grep -v grep | awk '{ print $2 }'` || true
#	kill -9 `ps -ef  | grep 'play.jar' | grep -v grep | awk '{ print $2 }'` || true
#
#	# start a play instance and invoke tests
#	cd $SANDBOX/web
#	echo "Starting play tests .. "
#	./$PLAY_VER/play test tserver &
#	echo "Waiting play starts .. " `date` 
#	sleep 10
#	echo "Running tests .. " `date`
#	wget http://localhost:9000/@tests/all -O index.html -t 6
#	echo ""
#	mv index.html $SANDBOX/web/tserver/test-result/index.html
#
#	# kill tcoffee test server instance 
#	kill -9 `ps -ef  | grep 'play test' | grep -v grep | awk '{ print $2 }'`
#	kill -9 `ps -ef  | grep 'play.jar' | grep -v grep | awk '{ print $2 }'`
#
#	# publish the tests
#	rm -rf $WORKSPACE/test-result
#	cp -r $SANDBOX/web/tserver/test-result $WORKSPACE/test-result
#
#	# check if the failure file exists
#	#if [ -e $WORKSPACE/test-result/result.failed ]; then exit 1; fi 
#}
#


#
# download perl packages 
#
function build_perlm() {
	echo "[ build_perlm ]"

	chmod +x $WORKSPACE/build/cpanm
	$WORKSPACE/build/cpanm -n -l $PERLM SOAP::Lite --reinstall
	$WORKSPACE/build/cpanm -n -l $PERLM XML::Simple --reinstall
	$WORKSPACE/build/cpanm -n -l $PERLM LWP --reinstall

}

#
# create platform independent paltform distribution
#
function pack_binaries() {
	echo "[ pack_binaries ]"

	# remove the t_coffee binaries from 'plugins' folder 
	# it have to exist in 'bin' folder  
	rm -rf $TCDIR/plugins/$OSNAME/t_coffee

	# invoke the install builder 
	mkdir -p $DIST_DIR
	"$INSTALLER" build $WORKSPACE/build/tcoffee-installer.xml --setvars product_version=$VERSION untared=$UNTARED osname=$OSNAME tcdir=$TCDIR outdir=$DIST_DIR outname=$INST_NAME
	
	# mac osx specific step 
	if [ $OSNAME == "macosx" ]
	then
	$WORKSPACE/build/mkdmg.sh $DIST_DIR/$INST_NAME.app
	mv $DIST_DIR/$INST_NAME.app.dmg $DIST_DIR/$INST_NAME.dmg 
	rm -rf $DIST_DIR/$INST_NAME.app
	fi
	
	# add execution attribute to the generated binary 
	if [ $OSNAME == "linux" ]
	then
	mv $DIST_DIR/$INST_NAME.run $DIST_DIR/$INST_NAME.bin
	chmod u+x $DIST_DIR/$INST_NAME.bin
	fi
	
}


function svn_tag() 
{
  echo "[ svn_tag ]"

  svn copy https://tcoffee.googlecode.com/svn/build/trunk https://tcoffee.googlecode.com/svn/build/tags/$VERSION -m "Tagging $VERSION" --username $_G_USR --password $_G_PWD
  svn copy https://tcoffee.googlecode.com/svn/tcoffee/trunk https://tcoffee.googlecode.com/svn/tcoffee/tags/$VERSION -m "Tagging $VERSION" --username $_G_USR --password $_G_PWD
}


#
#
# Execute all T-coffee core tasks (no server related)
#
function tcoffee() {
	echo "[ tcoffee ]"

	env
	clean
	build_dist
	build_perlm
	build_binaries	
	pack_binaries

	if [ $DO_TEST == 1 ]; then
	doc_test 
	fi

} 


#
# when at least a parameter is specified they are invoked as function call
#
if [ $# -gt 0 ] 
then
	while [ "$*" != "" ]
	do
		echo "Target: $1"
		$1
		shift
	done
else
    echo "Usage: build <target>"
    exit 1
fi
