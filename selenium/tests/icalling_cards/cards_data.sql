INSERT INTO cardgroups (id,owner_id) VALUES (3,3);

INSERT INTO `cards` (`id`, `balance`, `cardgroup_id`, `sold`, `number`, `pin`, `first_use`, `daily_charge_paid_till`, `frozen_balance`, `owner_id`, `callerid`)
VALUES 	(100, 1.78, 1,0, '3331111000', '7856', '2010-01-01 01:01:01', NULL, 0, 0, NULL),
	(101, 16.5, 3,0, '3331111001', '9812', '2010-02-01 01:02:01', NULL, 0, 3, NULL),
	(102, 2.50, 2,0, '3331111002', '9813', '2010-03-01 01:03:01', NULL, 0, 0, NULL),
	(103, 11.5, 3,0, '3331111003', '9814', '2010-04-01 01:04:01', NULL, 0, 3, NULL),
	(104, 20.5, 2,0, '3331111004', '9815', '2010-05-01 01:05:01', NULL, 0, 0, NULL),
	(105, 12.7, 1,0, '3331111006', '9816', '2010-01-02 01:01:01', NULL, 0, 0, NULL),
	(106, 12.5, 1,0, '3331111007', '9817', '2010-02-03 01:02:01', NULL, 0, 0, NULL),
	(107, 25.5, 3,0, '3331111008', '9818', '2010-03-04 01:03:01', NULL, 0, 3, NULL),
	(108, 13.5, 3,0, '3331111009', '9819', '2010-04-05 01:04:01', NULL, 0, 3, NULL),
	(109, 1.56, 1,0, '3331111010', '9820', '2010-05-06 01:05:01', NULL, 0, 0, NULL);