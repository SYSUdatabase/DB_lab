"""Validate deployable SQL extracted from the SQLCMD installation entry point."""

import unittest

from tools.repair_opening_inventory import procedure_source


class OpeningInventorySourceTests(unittest.TestCase):
    def test_execute_procedure_is_standalone_and_owner_controlled(self) -> None:
        source = procedure_source()
        self.assertTrue(source.startswith("CREATE OR ALTER PROCEDURE app.[Execute]"))
        self.assertIn("WITH EXECUTE AS OWNER", source)
        self.assertNotIn(":r ", source)
        self.assertNotIn("GRANT EXECUTE", source)


if __name__ == "__main__":
    unittest.main()
