#!/bin/sh
# USAGE:
#   source ./env.sh

export APP_HOME=`pwd`;
export PERL5LIB=$APP_HOME/local/lib/perl5:$APP_HOME/lib
export PATH=$PATH:$APP_HOME/local/bin
