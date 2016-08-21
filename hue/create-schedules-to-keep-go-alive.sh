#!/bin/bash

# The Hue Go turns itself off after 2 hours in standby mode.
# To use the Go as a wake-up light while powered by the battery, the next
# schedules are created to keep the Go alive during the night.

MAIN=$(dirname $0)/main.swift
GO_LIGHT_ID=5

${MAIN} create-schedule-light-alert W127/T23:00:15 ${GO_LIGHT_ID}
${MAIN} create-schedule-light-alert W127/T01:00:10 ${GO_LIGHT_ID}
${MAIN} create-schedule-light-alert W127/T03:00:05 ${GO_LIGHT_ID}
${MAIN} create-schedule-light-alert W127/T05:00:00 ${GO_LIGHT_ID}
