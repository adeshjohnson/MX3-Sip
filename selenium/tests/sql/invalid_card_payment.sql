INSERT INTO `acc_groups` (`id`, `name`, `only_view`, `group_type`, `description`) VALUES
(1, 'reseller_group_test', 0, 'reseller', ''),
(2, 'accountant_group_test', 0, 'accountant', '');

INSERT INTO `acc_group_rights` (`id`, `acc_group_id`, `acc_right_id`, `value`) VALUES
(1, 1, 31, 2),
(2, 1, 32, 0),
(3, 1, 33, 0),
(4, 1, 34, 0),
(5, 1, 35, 0),
(6, 1, 37, 0),
(7, 2, 1, 0),
(8, 2, 2, 0),
(9, 2, 3, 0),
(10, 2, 4, 0),
(11, 2, 5, 0),
(12, 2, 6, 0),
(13, 2, 7, 0),
(14, 2, 8, 0),
(15, 2, 9, 0),
(16, 2, 10, 0),
(17, 2, 11, 0),
(18, 2, 12, 0),
(19, 2, 13, 2),
(20, 2, 14, 0),
(21, 2, 15, 0),
(22, 2, 16, 0),
(23, 2, 17, 0),
(24, 2, 18, 2),
(25, 2, 19, 0),
(26, 2, 20, 0),
(27, 2, 21, 0),
(28, 2, 22, 0),
(29, 2, 23, 0),
(30, 2, 24, 0),
(31, 2, 25, 0),
(32, 2, 26, 0),
(33, 2, 27, 0),
(34, 2, 28, 0),
(35, 2, 29, 0),
(36, 2, 30, 0),
(37, 2, 36, 0);

update users set acc_group_id=1 where id=3;
update users set acc_group_id=2 where id=4;


INSERT INTO `cardgroups` (`id`, `name`, `description`, `price`, `setup_fee`, `ghost_min_perc`, `daily_charge`, `tariff_id`, `lcr_id`, `created_at`, `valid_from`, `valid_till`, `vat_percent`, `number_length`, `pin_length`, `dialplan_id`, `image`, `location_id`, `owner_id`, `tax_id`, `valid_after_first_use`, `ghost_balance_perc`, `use_external_function`, `allow_loss_calls`, `tell_cents`, `tell_balance_in_currency`, `solo_pinless`, `disable_voucher`, `hidden`) VALUES
(3, 'group_test_1', '', 0.000000000000000, 0.000000000000000, 100.000000000000000, 0.000000000000000, 2, 1, '2012-09-24 18:05:23', '2012-09-24 00:00:00', '2013-09-24 23:59:59', 0.000000000000000, 10, 4, 0, 'example.jpg', 1, 0, 4, 0, 100.000000000000000, 0, 0, 0, 'USD', 0, 0, 0),
(4, 'group_test_2', '', 0.000000000000000, 0.000000000000000, 100.000000000000000, 0.000000000000000, 3, 1, '2012-09-24 18:05:41', '2012-09-24 00:00:00', '2013-09-24 23:59:59', 0.000000000000000, 10, 4, 0, 'example.jpg', 2, 3, 8, 0, 100.000000000000000, 0, 0, 0, 'USD', 0, 0, 0),
(5, 'group_test_2.2', '', 0.000000000000000, 0.000000000000000, 100.000000000000000, 0.000000000000000, 3, 1, '2012-09-24 18:05:47', '2012-09-24 00:00:00', '2014-09-24 23:59:59', 0.000000000000000, 10, 4, 0, 'example.jpg', 2, 3, 9, 0, 100.000000000000000, 0, 0, 0, 'USD', 0, 0, 0);

INSERT INTO `cards` (`id`, `balance`, `cardgroup_id`, `sold`, `number`, `pin`, `first_use`, `daily_charge_paid_till`, `frozen_balance`, `owner_id`, `callerid`, `language`, `name`, `user_id`, `hidden`, `call_count`) VALUES
(22, 0.000000000000000, 3, 0, '2000000001', '8265', NULL, NULL, 0.000000000000000, 0, NULL, 'en', '', -1, 0, 0),
(23, 0.000000000000000, 3, 0, '2000000002', '3679', NULL, NULL, 0.000000000000000, 0, NULL, 'en', '', -1, 0, 0),
(24, 0.000000000000000, 3, 0, '2000000003', '0345', NULL, NULL, 0.000000000000000, 0, NULL, 'en', '', -1, 0, 0),
(25, 0.000000000000000, 3, 0, '2000000004', '9635', NULL, NULL, 0.000000000000000, 0, NULL, 'en', '', -1, 0, 0),
(26, 0.000000000000000, 3, 0, '2000000005', '2330', NULL, NULL, 0.000000000000000, 0, NULL, 'en', '', -1, 0, 0),
(27, 0.000000000000000, 4, 0, '2000000006', '1145', NULL, NULL, 0.000000000000000, 3, NULL, 'en', '', -1, 0, 0),
(28, 0.000000000000000, 4, 0, '2000000007', '7259', NULL, NULL, 0.000000000000000, 3, NULL, 'en', '', -1, 0, 0),
(29, 0.000000000000000, 4, 0, '2000000008', '3908', NULL, NULL, 0.000000000000000, 3, NULL, 'en', '', -1, 0, 0),
(30, 0.000000000000000, 5, 0, '2000000009', '7483', NULL, NULL, 0.000000000000000, 3, NULL, 'en', '', -1, 0, 0),
(31, 0.000000000000000, 5, 0, '2000000010', '9134', NULL, NULL, 0.000000000000000, 3, NULL, 'en', '', -1, 0, 0);
