return function()
	require("tests.test_fcp")()
	require("tests.test_html")()
	require("tests.test_just")()
	require("tests.test_localized")()
	require("tests.test_matcher")()
	require("tests.test_prop")()
	require("tests.test_scanplugins")()
	require("tests.test_strings")()
	require("tests.test_text")()
	require("tests.test_utf16")()
	
	hs.openConsole()
	print("Tests Complete!")
end