#!/bin/bash

echo -e "\033[0;32mDeploying updates to GitHub...\033[0m"

hugo

git submodule init

git submodule update

pushd public

git checkout -b temp

git add -A

msg="rebuilding site `date`"
if [ $# -eq 1]
    then msg="$1"
fi

git commit -m "$msg"

git checkout master

git merge temp 

git push origin master

git branch -d temp

popd
