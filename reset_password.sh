#!/usr/bin/env bash

# Call as follows:
#   ./sql/reset_password.sh <FAMILY_ID>

# Changes the password of the user to "password"
sqlite3 spring92.db "update family set password_hash='5BAA61E4C9B93F3F0682250B6CF8331B7EE68FD8' where id=$1;"
