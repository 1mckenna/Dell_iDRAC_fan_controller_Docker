#!/bin/bash

# Enable strict bash mode to stop the script if an uninitialized variable is used, if a command fails, or if a command with a pipe fails
# Not working in some setups : https://github.com/tigerblue77/Dell_iDRAC_fan_controller/issues/48
# set -euo pipefail

# Define global functions
# This function applies Dell's default dynamic fan control profile
function apply_Dell_fan_control_profile () {
  # Use ipmitool to send the raw command to set fan control to Dell default
  ipmitool -I $IDRAC_LOGIN_STRING raw 0x30 0x30 0x01 0x01 > /dev/null
  CURRENT_FAN_CONTROL_PROFILE="Dell default dynamic fan control profile"
}

function apply_NVIDIA_fan_control_profile () {
  # Use ipmitool to send the raw command to set fan control user controlled

  #Set fan speed to manual control
  ipmitool -I $IDRAC_LOGIN_STRING  raw 0x30 0x30 0x01 0x00  > /dev/null
  if [ "$GPU_TEMPERATURE" -ge 0 ] && [ "$GPU_TEMPERATURE" -le $GPU_TEMPERATURE_NORMAL_THRESHOLD ]
  then
    ipmitool -I $IDRAC_LOGIN_STRING  raw 0x30 0x30 0x01 0xff $(printf '0x%02x' 15)
  elif [ "$GPU_TEMPERATURE" -ge "$GPU_TEMPERATURE_NORMAL_THRESHOLD"+1 ] && [ "$GPU_TEMPERATURE" -le "$GPU_TEMPERATURE_NORMAL_THRESHOLD"+5 ]
  then
    ipmitool -I $IDRAC_LOGIN_STRING  raw 0x30 0x30 0x02 0xff $(printf '0x%02x' 25)
  elif [ "$GPU_TEMPERATURE" -ge "$GPU_TEMPERATURE_NORMAL_THRESHOLD"+6 ] && [ "$GPU_TEMPERATURE" -le "$GPU_TEMPERATURE_NORMAL_THRESHOLD"+10 ]
  then
    ipmitool -I $IDRAC_LOGIN_STRING  raw 0x30 0x30 0x02 0xff $(printf '0x%02x' 30)
  elif [ "$GPU_TEMPERATURE" -ge "$GPU_TEMPERATURE_NORMAL_THRESHOLD"+11 ] && [ "$GPU_TEMPERATURE" -le "$GPU_TEMPERATURE_NORMAL_THRESHOLD"+15 ]
  then
    ipmitool -I $IDRAC_LOGIN_STRING  raw 0x30 0x30 0x02 0xff $(printf '0x%02x' 35)
  elif [ "$GPU_TEMPERATURE" -ge "$GPU_TEMPERATURE_NORMAL_THRESHOLD"+16 ] && [ "$GPU_TEMPERATURE" -le "$GPU_TEMPERATURE_NORMAL_THRESHOLD"+20 ]
  then
    ipmitool -I $IDRAC_LOGIN_STRING  raw 0x30 0x30 0x02 0xff $(printf '0x%02x' 40)
  elif [ "$GPU_TEMPERATURE" -ge "$GPU_TEMPERATURE_NORMAL_THRESHOLD"+21 ] && [ "$GPU_TEMPERATURE" -le "$GPU_TEMPERATURE_NORMAL_THRESHOLD"+25 ]
  then
    ipmitool -I $IDRAC_LOGIN_STRING  raw 0x30 0x30 0x02 0xff $(printf '0x%02x' 50)
  elif [ "$GPU_TEMPERATURE" -ge "$GPU_TEMPERATURE_NORMAL_THRESHOLD"+26 ]
  then
    ipmitool -I $IDRAC_LOGIN_STRING  raw 0x30 0x30 0x02 0xff $(printf '0x%02x' 80)
  fi
  CURRENT_FAN_CONTROL_PROFILE="GPU Fan Profile ($DECIMAL_FAN_SPEED%)"
}

# This function applies a user-specified static fan control profile
function apply_user_fan_control_profile () {
  # Use ipmitool to send the raw command to set fan control to user-specified value
  ipmitool -I $IDRAC_LOGIN_STRING raw 0x30 0x30 0x01 0x00 > /dev/null
  ipmitool -I $IDRAC_LOGIN_STRING raw 0x30 0x30 0x02 0xff $HEXADECIMAL_FAN_SPEED > /dev/null
  CURRENT_FAN_CONTROL_PROFILE="User Static Fan ($DECIMAL_FAN_SPEED%)"
}

# Retrieve temperature sensors data using ipmitool
# Usage : retrieve_temperatures $IS_EXHAUST_TEMPERATURE_SENSOR_PRESENT $IS_CPU2_TEMPERATURE_SENSOR_PRESENT $IS_NVIDIA_GPU_PRESENT
function retrieve_temperatures () {
  if (( $# != 3 ))
  then
    printf "Illegal number of parameters.\nUsage: retrieve_temperatures \$IS_EXHAUST_TEMPERATURE_SENSOR_PRESENT \$IS_CPU2_TEMPERATURE_SENSOR_PRESENT \$IS_NVIDIA_GPU_PRESENT" >&2
    return 1
  fi
  local IS_EXHAUST_TEMPERATURE_SENSOR_PRESENT=$1
  local IS_CPU2_TEMPERATURE_SENSOR_PRESENT=$2
  local IS_NVIDIA_GPU_PRESENT=$3

  local DATA=$(ipmitool -I $IDRAC_LOGIN_STRING sdr type temperature | grep degrees)

  # Parse CPU data
  local CPU_DATA=$(echo "$DATA" | grep "3\." | grep -Po '\d{2}')
  CPU1_TEMPERATURE=$(echo $CPU_DATA | awk '{print $1;}')
  if $IS_CPU2_TEMPERATURE_SENSOR_PRESENT
  then
    CPU2_TEMPERATURE=$(echo $CPU_DATA | awk '{print $2;}')
  else
    CPU2_TEMPERATURE="-"
  fi

  if $IS_NVIDIA_GPU_PRESENT
  then
    #Parse GPU data
    GPU_TEMPERATURE=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader 2>/dev/null)
  else
    GPU_TEMPERATURE="-"
  fi

  # Parse inlet temperature data
  INLET_TEMPERATURE=$(echo "$DATA" | grep Inlet | grep -Po '\d{2}' | tail -1)

  # If exhaust temperature sensor is present, parse its temperature data
  if $IS_EXHAUST_TEMPERATURE_SENSOR_PRESENT
  then
    EXHAUST_TEMPERATURE=$(echo "$DATA" | grep Exhaust | grep -Po '\d{2}' | tail -1)
  else
    EXHAUST_TEMPERATURE="-"
  fi
}

function enable_third_party_PCIe_card_Dell_default_cooling_response () {
  # We could check the current cooling response before applying but it's not very useful so let's skip the test and apply directly
  ipmitool -I $IDRAC_LOGIN_STRING raw 0x30 0xce 0x00 0x16 0x05 0x00 0x00 0x00 0x05 0x00 0x00 0x00 0x00 > /dev/null
}

function disable_third_party_PCIe_card_Dell_default_cooling_response () {
  # We could check the current cooling response before applying but it's not very useful so let's skip the test and apply directly
  ipmitool -I $IDRAC_LOGIN_STRING raw 0x30 0xce 0x00 0x16 0x05 0x00 0x00 0x00 0x05 0x00 0x01 0x00 0x00 > /dev/null
}

# Returns :
# - 0 if third-party PCIe card Dell default cooling response is currently DISABLED
# - 1 if third-party PCIe card Dell default cooling response is currently ENABLED
# - 2 if the current status returned by ipmitool command output is unexpected
# function is_third_party_PCIe_card_Dell_default_cooling_response_disabled() {
#   THIRD_PARTY_PCIE_CARD_COOLING_RESPONSE=$(ipmitool -I $IDRAC_LOGIN_STRING raw 0x30 0xce 0x01 0x16 0x05 0x00 0x00 0x00)

#   if [ "$THIRD_PARTY_PCIE_CARD_COOLING_RESPONSE" == "16 05 00 00 00 05 00 01 00 00" ]; then
#     return 0
#   elif [ "$THIRD_PARTY_PCIE_CARD_COOLING_RESPONSE" == "16 05 00 00 00 05 00 00 00 00" ]; then
#     return 1
#   else
#     echo "Unexpected output: $THIRD_PARTY_PCIE_CARD_COOLING_RESPONSE" >&2
#     return 2
#   fi
# }

# Prepare traps in case of container exit
function gracefull_exit () {
  apply_Dell_fan_control_profile
  enable_third_party_PCIe_card_Dell_default_cooling_response
  echo "/!\ WARNING /!\ Container stopped, Dell default dynamic fan control profile applied for safety."
  exit 0
}

#START OF PRINTING FUNCTIONS (taken from https://github.com/gdbtek/linux-cookbooks/blob/main/libraries/util.bash)
function printTable()
{
    local -r delimiter="${1}"
    local -r tableData="$(removeEmptyLines "${2}")"
    local -r colorHeader="${3}"
    local -r displayTotalCount="${4}"

    if [[ "${delimiter}" != '' && "$(isEmptyString "${tableData}")" = 'false' ]]
    then
        local -r numberOfLines="$(trimString "$(wc -l <<< "${tableData}")")"

        if [[ "${numberOfLines}" -gt '0' ]]
        then
            local table=''
            local i=1

            for ((i = 1; i <= "${numberOfLines}"; i = i + 1))
            do
                local line=''
                line="$(sed "${i}q;d" <<< "${tableData}")"

                local numberOfColumns=0
                numberOfColumns="$(awk -F "${delimiter}" '{print NF}' <<< "${line}")"

                # Add Line Delimiter

                if [[ "${i}" -eq '1' ]]
                then
                    table="${table}$(printf '%s#+' "$(repeatString '#+' "${numberOfColumns}")")"
                fi

                # Add Header Or Body

                table="${table}\n"

                local j=1

                for ((j = 1; j <= "${numberOfColumns}"; j = j + 1))
                do
                    table="${table}$(printf '#|  %s' "$(cut -d "${delimiter}" -f "${j}" <<< "${line}")")"
                done

                table="${table}#|\n"

                # Add Line Delimiter

                if [[ "${i}" -eq '1' ]] || [[ "${numberOfLines}" -gt '1' && "${i}" -eq "${numberOfLines}" ]]
                then
                    table="${table}$(printf '%s#+' "$(repeatString '#+' "${numberOfColumns}")")"
                fi
            done

            if [[ "$(isEmptyString "${table}")" = 'false' ]]
            then
                local output=''
                output="$(echo -e "${table}" | column -s '#' -t -W 9 -c 165 | sed "s/+.*/$(printf '%*s' 163 "" | tr ' ' '-')/g")"
                if [[ "${colorHeader}" = 'true' ]]
                then
                    echo -e "\033[1;32m$(head -n 3 <<< "${output}")\033[0m"
                    tail -n +4 <<< "${output}"
                else
                    echo "${output}"
                fi
            fi
        fi

        if [[ "${displayTotalCount}" = 'true' && "${numberOfLines}" -ge '0' ]]
        then
            echo -e "\n\033[1;36mTOTAL ROWS : $((numberOfLines - 1))\033[0m"
        fi
    fi
}

function removeEmptyLines()
{
    local -r content="${1}"

    echo -e "${content}" | sed '/^\s*$/d'
}

function repeatString()
{
    local -r string="${1}"
    local -r numberToRepeat="${2}"

    if [[ "${string}" != '' && "$(isPositiveInteger "${numberToRepeat}")" = 'true' ]]
    then
        local -r result="$(printf "%${numberToRepeat}s")"
        echo -e "${result// /${string}}"
    fi
}

function isEmptyString()
{
    local -r string="${1}"

    if [[ "$(trimString "${string}")" = '' ]]
    then
        echo 'true' && return 0
    fi

    echo 'false' && return 1
}

function trimString()
{
    local -r string="${1}"

    sed 's,^[[:blank:]]*,,' <<< "${string}" | sed 's,[[:blank:]]*$,,'
}
#END OF PRINTING FUNCTIONS

# Trap the signals for container exit and run gracefull_exit function
trap 'gracefull_exit' SIGQUIT SIGKILL SIGTERM

# Prepare, format and define initial variables

# readonly DELL_FRESH_AIR_COMPLIANCE=45

# Check if FAN_SPEED variable is in hexadecimal format. If not, convert it to hexadecimal
if [[ $FAN_SPEED == 0x* ]]
then
  DECIMAL_FAN_SPEED=$(printf '%d' $FAN_SPEED)
  HEXADECIMAL_FAN_SPEED=$FAN_SPEED
else
  DECIMAL_FAN_SPEED=$FAN_SPEED
  HEXADECIMAL_FAN_SPEED=$(printf '0x%02x' $FAN_SPEED)
fi

# Log main informations given to the container
echo "iDRAC/IPMI host: $IDRAC_HOST"

# Check if the iDRAC host is set to 'local' or not then set the IDRAC_LOGIN_STRING accordingly
if [[ $IDRAC_HOST == "local" ]]
then
  # Check that the Docker host IPMI device (the iDRAC) has been exposed to the Docker container
  if [ ! -e "/dev/ipmi0" ] && [ ! -e "/dev/ipmi/0" ] && [ ! -e "/dev/ipmidev/0" ]; then
    echo "/!\ Could not open device at /dev/ipmi0 or /dev/ipmi/0 or /dev/ipmidev/0, check that you added the device to your Docker container or stop using local mode. Exiting." >&2
    exit 1
  fi
  IDRAC_LOGIN_STRING='open'
else
  echo "iDRAC/IPMI username: $IDRAC_USERNAME"
  # echo "iDRAC/IPMI password: $IDRAC_PASSWORD"
  echo "iDRAC/IPMI password: *****************"
  IDRAC_LOGIN_STRING="lanplus -H $IDRAC_HOST -U $IDRAC_USERNAME -P $IDRAC_PASSWORD"
fi

# Log the fan speed objective, CPU temperature threshold and check interval
echo "Fan speed objective: $DECIMAL_FAN_SPEED%"
echo "CPU temperature threshold: $CPU_TEMPERATURE_THRESHOLD°C"
echo "Check interval: ${CHECK_INTERVAL}s"
echo ""

# Define the interval for printing
readonly TABLE_HEADER_PRINT_INTERVAL=10
i=$TABLE_HEADER_PRINT_INTERVAL
# Set the flag used to check if the active fan control profile has changed
IS_DELL_FAN_CONTROL_PROFILE_APPLIED=true

# Check present sensors
IS_EXHAUST_TEMPERATURE_SENSOR_PRESENT=true
IS_CPU2_TEMPERATURE_SENSOR_PRESENT=true
IS_NVIDIA_GPU_PRESENT=true

retrieve_temperatures $IS_EXHAUST_TEMPERATURE_SENSOR_PRESENT $IS_CPU2_TEMPERATURE_SENSOR_PRESENT $IS_NVIDIA_GPU_PRESENT
if [ -z "$EXHAUST_TEMPERATURE" ]
then
  echo "No exhaust temperature sensor detected."
  IS_EXHAUST_TEMPERATURE_SENSOR_PRESENT=false
fi
if [ -z "$CPU2_TEMPERATURE" ]
then
  echo "No CPU2 temperature sensor detected."
  IS_CPU2_TEMPERATURE_SENSOR_PRESENT=false
fi
if [ -z "$GPU_TEMPERATURE" ]
then
  echo "No GPU temperature sensor detected."
  IS_NVIDIA_GPU_PRESENT=false
fi

# Output new line to beautify output if one of the previous conditions have echoed
if ! $IS_EXHAUST_TEMPERATURE_SENSOR_PRESENT || ! $IS_CPU2_TEMPERATURE_SENSOR_PRESENT || ! $IS_NVIDIA_GPU_PRESENT
then
  echo ""
fi

# Start monitoring
while true; do
  # Sleep for the specified interval before taking another reading
  sleep $CHECK_INTERVAL &
  SLEEP_PROCESS_PID=$!

  retrieve_temperatures $IS_EXHAUST_TEMPERATURE_SENSOR_PRESENT $IS_CPU2_TEMPERATURE_SENSOR_PRESENT $IS_NVIDIA_GPU_PRESENT

  # Define functions to check if CPU 1 and CPU 2 temperatures are above the threshold
  function CPU1_OVERHEAT () { [ $CPU1_TEMPERATURE -gt $CPU_TEMPERATURE_THRESHOLD ]; }
  if $IS_CPU2_TEMPERATURE_SENSOR_PRESENT
  then
    function CPU2_OVERHEAT () { [ $CPU2_TEMPERATURE -gt $CPU_TEMPERATURE_THRESHOLD ]; }
  fi
  if $IS_NVIDIA_GPU_PRESENT
  then
    function GPU_OVERHEAT () { [ $GPU_TEMPERATURE -gt $GPU_TEMPERATURE_NORMAL_THRESHOLD ]; }
  fi

  # Initialize a variable to store the comments displayed when the fan control profile changed
  COMMENT=" -"
  # Check if CPU 1 is overheating then apply Dell default dynamic fan control profile if true
  if CPU1_OVERHEAT
  then
    apply_Dell_fan_control_profile

    if ! $IS_DELL_FAN_CONTROL_PROFILE_APPLIED
    then
      IS_DELL_FAN_CONTROL_PROFILE_APPLIED=true

      # If CPU 2 temperature sensor is present, check if it is overheating too.
      # Do not apply Dell default dynamic fan control profile as it has already been applied before
      if $IS_CPU2_TEMPERATURE_SENSOR_PRESENT && CPU2_OVERHEAT
      then
        COMMENT="CPU 1 and CPU 2 temperatures are too high"
      else
        COMMENT="CPU 1 temperature is too high"
      fi
    fi
  # If CPU 2 temperature sensor is present, check if it is overheating then apply Dell default dynamic fan control profile if true
  elif $IS_CPU2_TEMPERATURE_SENSOR_PRESENT && CPU2_OVERHEAT
  then
    apply_Dell_fan_control_profile

    if ! $IS_DELL_FAN_CONTROL_PROFILE_APPLIED
    then
      IS_DELL_FAN_CONTROL_PROFILE_APPLIED=true
      COMMENT="CPU 2 temperature is too high"
    fi
  elif $IS_NVIDIA_GPU_PRESENT && GPU_OVERHEAT && !$IS_DELL_FAN_CONTROL_PROFILE_APPLIED
  then
    apply_NVIDIA_fan_control_profile
  else
    apply_user_fan_control_profile

    # Check if user fan control profile is applied then apply it if not
    if $IS_DELL_FAN_CONTROL_PROFILE_APPLIED
    then
      IS_DELL_FAN_CONTROL_PROFILE_APPLIED=false
      COMMENT="CPU Temp OK (<= $CPU_TEMPERATURE_THRESHOLD C)"
    fi
  fi

  # Enable or disable, depending on the user's choice, third-party PCIe card Dell default cooling response
  # No comment will be displayed on the change of this parameter since it is not related to the temperature of any device (CPU, GPU, etc...) but only to the settings made by the user when launching this Docker container
  if $DISABLE_THIRD_PARTY_PCIE_CARD_DELL_DEFAULT_COOLING_RESPONSE
  then
    disable_third_party_PCIe_card_Dell_default_cooling_response
    THIRD_PARTY_PCIE_CARD_DELL_DEFAULT_COOLING_RESPONSE_STATUS="Disabled"
  else
    enable_third_party_PCIe_card_Dell_default_cooling_response
    THIRD_PARTY_PCIE_CARD_DELL_DEFAULT_COOLING_RESPONSE_STATUS="Enabled"
  fi

  # Print temperatures, active fan control profile and comment if any change happened during last time interval
  if [ $i -eq $TABLE_HEADER_PRINT_INTERVAL ]
  then
    TABLE_DATA="Date & time,Inlet,CPU 1,CPU 2,GPU,Exhaust,Active Fan Profile,3rd-party Cooling Response,Comment\n"
    i=0
  fi
  TABLE_DATA+="$(date +"%d-%m-%Y %T"),$INLET_TEMPERATURE C,$CPU1_TEMPERATURE C,$CPU2_TEMPERATURE C,$GPU_TEMPERATURE C,$EXHAUST_TEMPERATURE C,$CURRENT_FAN_CONTROL_PROFILE,$THIRD_PARTY_PCIE_CARD_DELL_DEFAULT_COOLING_RESPONSE_STATUS,$COMMENT    \n"
  clear
  printTable "," "$TABLE_DATA" true
  ((i++))
  wait $SLEEP_PROCESS_PID
done
