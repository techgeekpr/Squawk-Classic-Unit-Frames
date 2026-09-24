if type(SquawkClassicUFDB) == "table" then
	SquawkClassicUF_Restore = SquawkClassicUF_Restore or {}
	SquawkClassicUF_Restore[#SquawkClassicUF_Restore + 1] = SquawkClassicUFDB
	SquawkClassicUFDB = nil
end
