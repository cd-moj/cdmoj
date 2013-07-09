#!/bin/bash

mkdir submissions data
chmod 777 submissions data

for i in $(ls -lrt prova/*); do
    for user in $(cut -d: -f1 passwd); do
        mkdir data/$user
        NOME="$(basename $i)"
        NOME="$(cut -d: -f1,2 <<< $NOME)"
        printf "none\nnone\n" > data/$user

        chmod 777 -R data/$user
    done

done
