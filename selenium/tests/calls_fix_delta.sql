Update calls set user_id = 5, src_device_id = 7 where id IN (22,23);
Update calls set reseller_price = 4 where reseller_price > 0;
Update calls set user_price = 5 where user_price > 0;
Update calls set did_price = 2 where did_price > 0;
Update calls set did_inc_price = 3 where did_inc_price > 0;
Update calls set provider_price = 1 where provider_price > 0;
Update calls set src_device_id = 7 where user_id = 5;
Update calls set src_device_id = 6 where user_id = 3;
Update calls set src_device_id = 2 where user_id = 2;
Update calls set src_device_id = 5 where user_id = 0;
Update calls set dst_device_id = 0 where user_id > -1;
Update calls set user_id = 5 where src_device_id = 7;
Update calls set user_id = 3 where src_device_id = 6;
Update calls set user_id = 2 where src_device_id = 2;
Update calls set user_id = 0 where src_device_id = 5;
Update calls set card_id = 21 where card_id = 22;
Update calls set user_id=2 where src_device_id=4;
Update calls set user_id=2 where src_device_id=2;
Update calls set user_id=2 where src_device_id=3;
Update calls set user_id=5 where src_device_id=7;
Update calls set user_id=3 where src_device_id=6;
Update calls set user_id=-1 where src_device_id=0;
Update calls set user_id=0 where src_device_id=5;
#sync data
UPDATE calls JOIN devices ON calls.dst_device_id = devices.id SET calls.dst_user_id = devices.user_id; 
