#!/bin/bash
#
# Using pktgen "burst" option (use -b $N)
#  - To boost max performance
#  - Avail since: kernel v3.18
#   * commit 38b2cf2982dc73 ("net: pktgen: packet bursting via skb->xmit_more")
#  - This avoids writing the HW tailptr on every driver xmit
#  - The performance boost is impressive, see commit and blog [2]
#  - If correctly tuned[1], single CPU 10G wirespeed small pkts is possible
#
# Notice: On purpose generates a single (UDP) flow towards target,
#   reason behind this is to only overload/activate a single CPU on
#   target host.  And no randomness for pktgen also makes it faster.
#
# Tuning see:
#  [1] http://netoptimizer.blogspot.dk/2014/06/pktgen-for-network-overload-testing.html
#  [2] http://netoptimizer.blogspot.dk/2014/10/unlocked-10gbps-tx-wirespeed-smallest.html
#
basedir=`dirname $0`
source ${basedir}/functions.sh
root_check_run_with_sudo "$@"
source ${basedir}/parameters.sh

# Base Config
DELAY="0"  # Zero means max speed
COUNT="0"  # Zero means indefinitely
[ -z "$CLONE_SKB" ] && CLONE_SKB="100000"

# Packet setup
# (example of setting default params in your script)
[ -z "$DEST_IP" ] && DEST_IP="198.18.0.42"
[ -z "$DST_MAC" ] && DST_MAC="90:e2:ba:ff:ff:ff"
[ -z "$BURST" ] && BURST=32

# General cleanup everything since last run
pg_ctrl "reset"

# Threads are specified with parameter -t value in $THREADS
for ((thread = 0; thread < $THREADS; thread++)); do
    dev=${DEV}@${thread}

    # Add remove all other devices and add_device $dev to thread
    pg_thread $thread "rem_device_all"
    pg_thread $thread "add_device" $dev

    # Base config
    pg_set $dev "flag QUEUE_MAP_CPU"
    pg_set $dev "count $COUNT"
    pg_set $dev "clone_skb $CLONE_SKB"
    pg_set $dev "pkt_size $PKT_SIZE"
    pg_set $dev "delay $DELAY"
    pg_set $dev "flag NO_TIMESTAMP"

    # Destination
    pg_set $dev "dst_mac $DST_MAC"
    pg_set $dev "dst $DEST_IP"

    # Setup burst
    pg_set $dev "burst $BURST"
done

# Run if user hits control-c
function control_c() {
    # Print results
    for ((thread = 0; thread < $THREADS; thread++)); do
	dev=${DEV}@${thread}
	echo "Device: $dev"
	cat /proc/net/pktgen/$dev | grep -A2 "Result:"
    done
}
# trap keyboard interrupt (Ctrl-C)
trap control_c SIGINT

echo "Running... ctrl^C to stop" >&2
pg_ctrl "start"
