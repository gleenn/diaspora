#!/bin/bash

echo "*************************************************************************************************" &&
echo "*                                  ruby 1.8.7-p249 build                                        *" &&
echo "*************************************************************************************************" &&
echo "" &&
rm -f Gemfile.lock &&
source /usr/local/rvm/scripts/rvm &&
rvm use ruby-1.8.7-p249@diaspora &&
bundle install &&
bundle exec rake cruise
