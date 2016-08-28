#!/bin/bash

MAIN=$(dirname $0)/main.swift

for scheduleId in ${@:1}
do
  ${MAIN} delete-schedule ${scheduleId}
done
