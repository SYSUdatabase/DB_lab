"""用真实历史缺陷验证生成器，而非仅重复其实现。"""

import copy
import unittest
from datetime import timedelta

from tools import datagen
from tools.timeline import (
    Tables,
    credit_events,
    moment,
    number,
    repair_accounts,
    repair_timeline,
    valid_at,
    validate_dataset,
)


def dataset() -> Tables:
    return copy.deepcopy({name: list(rows) for name, _, rows in datagen.table_specs})


class TimelineTests(unittest.TestCase):
    def test_missing_parent_is_rejected_before_serialization(self) -> None:
        tables = dataset()
        tables["TokenUsageLogs"][0]["account_id"] = 999999
        with self.assertRaisesRegex(ValueError, "引用不存在"):
            validate_dataset(tables)

    def test_fixed_dataset_and_serialized_sql(self) -> None:
        validate_dataset(dataset())
        self.assertEqual(datagen.build_sql(), datagen.OUT_PATH.read_text(encoding="utf-8"))
        self.assertEqual(len(datagen.usage_logs), 3000)

    def test_order_before_registration_is_rejected(self) -> None:
        tables = dataset()
        order = tables["Orders"][0]
        user = next(row for row in tables["Users"] if row["user_id"] == order["user_id"])
        user["created_at"] = moment(order, "created_at") + timedelta(seconds=1)
        with self.assertRaisesRegex(ValueError, "订单早于注册"):
            validate_dataset(tables)

    def test_usage_before_registration_is_rejected(self) -> None:
        tables = dataset()
        usage = tables["TokenUsageLogs"][0]
        user = next(row for row in tables["Users"] if row["user_id"] == usage["user_id"])
        usage["used_at"] = moment(user, "created_at") - timedelta(seconds=1)
        with self.assertRaisesRegex(ValueError, "调用早于注册"):
            validate_dataset(tables)

    def test_final_balance_cannot_hide_historical_overdraft(self) -> None:
        tables = dataset()
        usage = next(row for row in tables["TokenUsageLogs"] if row["user_id"] == 32)
        funding = [
            event
            for event in credit_events(tables["Orders"], tables["OrderDetails"], tables["Products"])
            if event[2] == 32 and event[3] == "OpenAI"
        ]
        usage["used_at"] = min(event[0] for event in funding) - timedelta(seconds=1)
        with self.assertRaisesRegex(ValueError, "历史余额为负"):
            validate_dataset(tables)

    def test_payment_at_same_second_precedes_consumption(self) -> None:
        tables = dataset()
        usage = next(row for row in tables["TokenUsageLogs"] if row["user_id"] == 32)
        funding = [
            event[0]
            for event in credit_events(tables["Orders"], tables["OrderDetails"], tables["Products"])
            if event[2] == 32 and event[3] == "OpenAI"
        ]
        usage["used_at"] = min(funding)
        validate_dataset(tables)

    def test_expiry_is_exclusive_and_null_expiry_is_supported(self) -> None:
        account = copy.deepcopy(datagen.accounts[6])
        expiry = moment(account, "expires_at")
        self.assertTrue(valid_at(account, expiry - timedelta(seconds=1)))
        self.assertFalse(valid_at(account, expiry))
        account["expires_at"] = None
        self.assertTrue(valid_at(account, expiry))

    def test_expired_usage_is_rejected(self) -> None:
        tables = dataset()
        usage = next(row for row in tables["TokenUsageLogs"] if row["account_id"] == 7)
        usage["used_at"] = moment(tables["UpstreamAccount"][6], "expires_at")
        with self.assertRaisesRegex(ValueError, "调用不在账号有效期"):
            validate_dataset(tables)

    def test_provider_mismatch_is_rejected(self) -> None:
        tables = dataset()
        usage = next(row for row in tables["TokenUsageLogs"] if row["account_id"] == 1)
        usage["account_id"] = 4
        with self.assertRaisesRegex(ValueError, "provider 不匹配"):
            validate_dataset(tables)

    def test_no_eligible_account_fails_explicitly(self) -> None:
        usage = copy.deepcopy(datagen.usage_logs[:1])
        with self.assertRaisesRegex(ValueError, "没有同 provider"):
            repair_accounts(usage, [], datagen.products)

    def test_insufficient_credit_cannot_be_scheduled(self) -> None:
        usage = copy.deepcopy(datagen.usage_logs[:1])
        with self.assertRaisesRegex(ValueError, "已付款额度不足"):
            repair_timeline(
                copy.deepcopy(datagen.users),
                datagen.orders,
                [],
                datagen.products,
                usage,
            )

    def test_business_totals_are_preserved(self) -> None:
        self.assertEqual(sum(number(row, "tokens_used") for row in datagen.usage_logs), 6040100)
        self.assertEqual(
            sum(number(row, "remaining_tokens") for row in datagen.token_balances),
            86909900,
        )


if __name__ == "__main__":
    unittest.main()
