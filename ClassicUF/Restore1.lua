if type(ClassicUFDB) == "table" then
	ClassicUF_Restore = ClassicUF_Restore or {}
	ClassicUF_Restore[#ClassicUF_Restore + 1] = ClassicUFDB
	ClassicUFDB = nil
end
