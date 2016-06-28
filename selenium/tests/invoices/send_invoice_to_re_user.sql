INSERT INTO `devices` (`id`, `name`, `host`, `secret`, `context`, `ipaddr`, `port`, `regseconds`, `accountcode`, `callerid`, `extension`, `voicemail_active`, `username`, `device_type`, `user_id`, `primary_did_id`, `works_not_logged`, `forward_to`, `record`, `transfer`, `disallow`, `allow`, `deny`, `permit`, `nat`, `qualify`, `fullcontact`, `canreinvite`, `devicegroup_id`, `dtmfmode`, `callgroup`, `pickupgroup`, `fromuser`, `fromdomain`, `trustrpid`, `sendrpid`, `insecure`, `progressinband`, `videosupport`, `location_id`, `description`, `istrunk`, `cid_from_dids`, `pin`, `tell_balance`, `tell_time`, `tell_rtime_when_left`, `repeat_rtime_every`, `t38pt_udptl`, `regserver`, `ani`, `promiscredir`, `timeout`, `process_sipchaninfo`, `temporary_id`, `allow_duplicate_calls`, `call_limit`, `faststart`, `h245tunneling`, `latency`, `grace_time`, `recording_to_email`, `recording_keep`, `recording_email`) VALUES
                       (113,'101','dynamic','101','mor_local','0.0.0.0',0,1175892667,2,'\"101\" <101>','101',0,'101','IAX2',12,0,1,0,0,'no','all','all','0.0.0.0/0.0.0.0','0.0.0.0/0.0.0.0','yes','yes','','no',NULL,'rfc2833',NULL,NULL,NULL,NULL,'no','no','no','never','no',1,'Test Device #1',0,0,NULL,0,0,60,60,'no',NULL,0,'no',60,0,NULL,0,0,'yes','yes',0,0,0,0,NULL);

INSERT INTO `calls`
(`id`, `calldate`          , `clid`               , `src`       , `dst`       , `dcontext`, `channel`, `dstchannel`, `lastapp`, `lastdata`, `duration`, `billsec`, `disposition`, `amaflags`, `accountcode`, `uniqueid`   , `userfield`, `src_device_id`, `dst_device_id`, `processed`, `did_price`, `card_id`, `provider_id`, `provider_rate`, `provider_billsec`, `provider_price`, `user_id`, `user_rate`, `user_billsec`, `user_price`, `reseller_id`, `reseller_rate`, `reseller_billsec`, `reseller_price`, `partner_id`, `partner_rate`, `partner_billsec`, `partner_price`, `prefix`, `server_id`, `hangupcause`, `callertype`, `peerip`, `recvip`, `sipfrom`, `uri`, `useragent`, `peername`, `t38passthrough`, `did_inc_price`, `did_prov_price`, `localized_dst`, `did_provider_id`, `did_id`, `originator_ip`, `terminator_ip`, `real_duration`, `real_billsec`, `did_billsec`)
VALUES
# outgoing 2011-01-01
(122   ,'2013-01-01 00:00:01',''                    ,'101'        ,'123123'     ,''         ,''        ,''           ,''        ,''         ,10         ,20        ,'ANSWERED'    ,0          ,'2'           ,'1232113370.3',''          ,113               ,0               ,0           ,0           ,0         ,1             ,0               ,0                  ,1                ,12         ,0           ,1              ,2            ,11             ,0               ,0                  ,0                ,0            ,0              ,0                 ,0               ,'1231'   ,1           ,16            ,'Local'      ,''       ,''       ,''        ,''    ,''          ,''         ,0                ,0               ,0                ,'123123'        ,0                 ,0        ,''              ,''              ,0               ,0              ,0);
