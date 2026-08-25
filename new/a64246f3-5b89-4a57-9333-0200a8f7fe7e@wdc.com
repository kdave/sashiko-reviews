From prvsi05fe0dd=Johannes.Thumshirn@wdc.com Tue Aug 25 12:28:59 2026
Message-ID: <a64246f3-5b89-4a57-9333-0200a8f7fe7e@wdc.com>
Date: Tue, 25 Aug 2026 12:28:42 +0200
Subject: Re: Fwd [sashiko-bot@kernel.org: Re: [PATCH] btrfs: zoned: handle
 RAID profiles in btrfs_can_activate_zone()]
From: Johannes Thumshirn <johannes.thumshirn@wdc.com>

On 8/24/26 6:58 PM, David Sterba wrote:
> Review comments don't sound unreasonable:
>
> - the switch allows to continue for multi-device filesystems
>
> ----- Forwarded message from sashiko-bot@kernel.org -----
>
> Thank you for your contribution! Sashiko AI review found 2 potential issue(s) to consider:
>
> New issues:
> - [High] btrfs_can_activate_zone() incorrectly returns true for multi-device RAID profiles when only a single device has available active zones, leading to chunk activation failures, infinite allocation loops, and premature ENOSPC.

This situation must never happen, if this happens, we have a bug 
elsewhere. If only one zone in a block-group is sequential only, active 
zone tracking is done and the total number of max_active_zones of the FS 
should be the min() of all maz of the devices in the FS.


> Pre-existing issues:
> - [High] btrfs_zone_activate() permanently leaks reserved_active_zones and temporarily leaks active_zones_left if a multi-stripe block group fails to activate midway through its stripes.
> --

That one I need to look into.


> --- Patch [1]: [PATCH] btrfs: zoned: handle RAID profiles in btrfs_can_activate_zone() ---
> commit d42887c3b92e69264b1963962b3b0d4b608afc5e
> Author: Johannes Thumshirn <johannes.thumshirn@wdc.com>
>
> btrfs: zoned: handle RAID profiles in btrfs_can_activate_zone()
>
> This commit adds support for RAID profiles in btrfs_can_activate_zone(),
> evaluating multi-device profiles to check if they can be activated based on
> available active zones.
>
>> --- a/fs/btrfs/zoned.c
>> +++ b/fs/btrfs/zoned.c
> [ ... ]
>
>> @@ -2691,6 +2691,11 @@ bool btrfs_can_activate_zone(struct btrfs_fs_devices *fs_devices, u64 flags)
>>   
>>   		switch (flags & BTRFS_BLOCK_GROUP_PROFILE_MASK) {
>>   		case 0: /* single */
>> +		case BTRFS_BLOCK_GROUP_RAID0:
>> +		case BTRFS_BLOCK_GROUP_RAID1:
>> +		case BTRFS_BLOCK_GROUP_RAID1C3:
>> +		case BTRFS_BLOCK_GROUP_RAID1C4:
>> +		case BTRFS_BLOCK_GROUP_RAID10:
>>   			ret = (atomic_read(&zinfo->active_zones_left) >= (1 + reserved));
>>   			break;
>>   		case BTRFS_BLOCK_GROUP_DUP:
>>   			ret = (atomic_read(&zinfo->active_zones_left) >= (2 + reserved));
>>   			break;
>>   		}
>>   		if (ret)
>>   			break;
> [Severity: High]
> Does this code incorrectly return true for multi-device RAID profiles when
> only a single device has available active zones?
>
> Since the loop breaks early after finding just one device that evaluates to
> true, and RAID profiles span multiple devices (e.g., RAID1 requires 2
> devices), a single device with available active zones bypasses setting
> BTRFS_FS_NEED_ZONE_FINISH.
>
> Will this allow can_allocate_chunk_zoned() to proceed and allocate chunks
> that cannot actually be activated, potentially creating an infinite chunk
> allocation loop when find_free_extent() tries to drop and retry?
>
>
> [Severity: High]
> This is a pre-existing issue, but it interacts with the newly added
> multi-device RAID logic. Does btrfs_zone_activate() permanently leak
> reserved_active_zones if a multi-stripe block group fails to activate
> midway through its stripes?
>
> If btrfs_can_activate_zone() allows a multi-device chunk to be allocated
> but only some devices have active zones available, btrfs_zone_activate()
> will succeed on the first stripe but fail on a subsequent one:
>
> fs/btrfs/zoned.c:btrfs_zone_activate() {
> ...
> 		if (!btrfs_dev_set_active_zone(device, physical)) {
> 			/* Cannot activate the zone */
> 			ret = false;
> 			goto out_unlock;
> 		}
> 		if (!is_data)
> 			zinfo->reserved_active_zones--;
> ...
> }
>
> The error path fails to roll back the decremented reserved_active_zones.
> Because BLOCK_GROUP_FLAG_ZONE_IS_ACTIVE is never set, do_zone_finish()
> will silently skip the cleanup:
>
> fs/btrfs/zoned.c:do_zone_finish() {
> 	spin_lock(&block_group->lock);
> 	if (!test_bit(BLOCK_GROUP_FLAG_ZONE_IS_ACTIVE, &block_group->runtime_flags)) {
> 		spin_unlock(&block_group->lock);
> 		return 0;
> 	}
> ...
> }
>
> Can this permanent leak of reserved_active_zones eventually prevent
> metadata block groups from activating and cause filesystem deadlocks
> under heavy load?
>


