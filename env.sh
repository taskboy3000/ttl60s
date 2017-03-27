#!/bin/sh
# USAGE:
#   source ./env.sh

export APP_HOME=`pwd`;
export PERL5LIB=$APP_HOME/local/lib/perl5:$APP_HOME/local/lib/perl5/arm-linux-gnueabihf-thread-multi-64int:$APP_HOME/lib
export PATH=$PATH:$APP_HOME/local/bin
export MOJO_LISTEN='http://*:4000/'

if [ ! -f ttl60s.secret ];
then
    echo "WARN: missing ttl60s.secret file"
fi
