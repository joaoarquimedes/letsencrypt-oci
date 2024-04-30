#!/usr/bin/env bash

# Message Function
# Function aimed at receiving the type of message and printing it to the standard output STDOUT.
# The type of message to be printed can also be passed, whether it is error, warning, alert, info, success, or loading.

# Usage Example:
# Messages "This is a standard message to be printed."
# Messages -E "This is an error type message."
# Messages -W "This is a warning type message."
# Messages -A "This is an alert type message."
# Messages -C "This is an attention type message (Care)."
# Messages -I "This is an info type message."
# Messages -S "This is a success type message."
# Messages -L "This is a loading type message."
# ...

# If the -n parameter is passed as an argument, the line will not break, thereby supporting one message in front of another.
# Example:
# Messages -I "Test message..." -n
# Messages " ... continuing message on the same line as before."
#
function Messages() {
   # Ativando cores
   ColorError='\e[41;37m'
   ColorWarning='\e[31m'
   ColorAlert='\e[33m'
   ColorCare='\e[31m'
   ColorInfo='\e[36m'
   ColorSuccess='\e[32m'
   ColorF='\e[m'

   local mess
   local newl=true

   case "$1" in
      -E | -e) mess="[ ${ColorError}erro${ColorF} ] ${2}";;
      -W | -w) mess="[ ${ColorWarning}warn${ColorF} ] ${2}";;
      -A | -a) mess="[ ${ColorAlert}aler${ColorF} ] ${2}";;
      -C | -c) mess="[ ${ColorCare}atte${ColorF} ] ${2}";;
      -I | -i) mess="[ ${ColorInfo}info${ColorF} ] ${2}";;
      -S | -s) mess="[ ${ColorSuccess} ok ${ColorF} ] ${2}";;
      -L | -l) mess="[ .... ] ${2}";;
      *)       mess="$1";;
   esac

   # Checking if verbose mode is active and if there is a message.
   [ "$Verbose" = true -a -n "$mess" ] || return

   # Checking if the -n argument has been passed.
   [ "$2" = "-n" -o "$3" = "-n" ] && newl=false

   # Printing the message.
   [ "$newl" = "true" ] && echo -e "$mess" || echo -e -n "$mess"
}
