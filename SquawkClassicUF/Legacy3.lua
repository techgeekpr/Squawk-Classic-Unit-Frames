-- The addon used to be called ClassicUF.  Park anything saved under the old
-- name so the settings can be carried over once, then get out of the way.
if type(ClassicUFDB) == "table" then
	SquawkClassicUF_Legacy = SquawkClassicUF_Legacy or {}
	SquawkClassicUF_Legacy[#SquawkClassicUF_Legacy + 1] = ClassicUFDB
	ClassicUFDB = nil
end
