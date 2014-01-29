#!/bin/sh
#
# Copyright (C) 2009 OpenWrt.org
#
#

. /lib/ar71xx.sh

status_led=""

led_set_attr() {
	[ -f "/sys/class/leds/$1/$2" ] && echo "$3" > "/sys/class/leds/$1/$2"
}

status_led_set_timer() {
	led_set_attr $status_led "trigger" "timer"
	led_set_attr $status_led "delay_on" "$1"
	led_set_attr $status_led "delay_off" "$2"
}

status_led_on() {
	led_set_attr $status_led "trigger" "none"
	led_set_attr $status_led "brightness" 255
}

status_led_off() {
	led_set_attr $status_led "trigger" "none"
	led_set_attr $status_led "brightness" 0
}

get_status_led() {
	case $(ar71xx_board_name) in
	tl-wr1043nd)
		status_led="tp-link:green:system"
		;;
	esac;
}

set_state() {
	get_status_led

	case "$1" in
	preinit)
		insmod leds-gpio
		insmod ledtrig-default-on
		insmod ledtrig-timer
		status_led_set_timer 200 200
		;;
	failsafe)
		status_led_set_timer 50 50
		;;
	done)
		status_led_on
		;;
	esac
}
