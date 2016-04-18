#! /usr/bin/env bash

# This script parses the AWS metadata service's block device mappings, then
# queries /proc/partitions for sizes and partition tables. Any unpartitioned
# volumes (determined via `parted --list`; volumes without a file system appear
# as "unrecognised disk label" volumes) will have an ext4 file system added.
#
# As this uses the metadata service rather than ec2:DescribeInstances, this
# will not work with volumes mounted after instance startup by default. If you
# are comfortable with this being run on _every device_ (which will also pick up
# dynamically attached volumes), then set
#
# ```
# PROBE_ALL_VOLUMES=1
# ```
#
# before invoking.
#
# Also note that this expects the modern Xen virtual device naming of 'xvdN',
# rather than the old-style 'sdN' naming, and will convert EBS mappings to
# the correct format.
#
# -eropple
# 18 Apr 2016

BAIL=0
REQUIRED_COMMANDS=( 'parted' 'curl' )

if [[ `sudo whoami` != 'root' ]]
  then

  echo "!!! Must be invoked as root."
  BAIL=1
fi

for REQUIRED_CMD in ${REQUIRED_COMMANDS[@]}; do
  which $REQUIRED_CMD > /dev/null
  if [[ $? -ne 0 ]]
    then

    echo "!!! cannot find '${REQUIRED_CMD}' on \$PATH, please install."
    BAIL=1
  fi
done

if [[ $BAIL -ne 0 ]]
  then

  echo "... One or more errors found, exiting."
  exit 1
fi

DEVICES=()

METADATA_URL='http://169.254.169.254/latest/meta-data'
BLOCK_MAPPING_URL="${METADATA_URL}/block-device-mapping"

if [[ $PROBE_ALL_VOLUMES -ne 1 ]]
  then

  EBS_VOLUMES=`curl -s ${BLOCK_MAPPING_URL}/ | grep -v ami | grep -v root`
  for EBS_NAME in $EBS_VOLUMES; do
    DEVICE_NAME=$( curl -s ${BLOCK_MAPPING_URL}/${EBS_NAME} | sed 's,^sd,xvd,' | sed 's,^,/dev/,' )

    DEVICES+=( $DEVICE_NAME )
  done
else
  ALL_DEVICES=$( parted --list --machine | grep -Eow '/dev/xvd[a-z]+' )
  for ALL_DEVICES in $ALL_DEVICES; do
    DEVICES+=( $ALL_DEVICES )
  done
fi

for DEVICE in ${DEVICES[@]}; do
  echo "  - Probing '${DEVICE}'"

  parted --list --machine | grep ${DEVICE} | grep 'unrecognised' > /dev/null

  if [[ $? -ne 0 ]]
    then

    echo "    - Partition table exists for '${DEVICE}', not creating new file system."
  else
    echo "    - No partition table found for '${DEVICE}', making file system."
    mkfs -t ext4 ${DEVICE}
  fi
done
