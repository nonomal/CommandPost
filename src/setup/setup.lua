local modpath, frameworkspath, prettypath, fullpath, configdir, docstringspath, hasinitfile, autoload_extensions = ...

-- Original Hammerspoon Paths:
--package.path=configdir.."/?.lua"..";"..configdir.."/?/init.lua"..";"..configdir.."/Spoons/?.spoon/init.lua"..";"..package.path..";"..modpath.."/?.lua"..";"..modpath.."/?/init.lua"
--package.cpath=configdir.."/?.so"..";"..package.cpath..";"..frameworkspath.."/?.dylib"

-- CommandPost Paths:
package.path=configdir.."/?.lua"..";"..configdir.."/?/init.lua"..";"..modpath.."/?.lua"..";"..modpath.."/?/init.lua"
package.cpath=configdir.."/?.so"..";"..modpath.."/?.so;"..frameworkspath.."/?.dylib"

print("-- package.path: "..package.path)
print("-- package.cpath: "..package.cpath)

package.preload['hs.application.watcher']   = function() return require("hs.libapplicationwatcher") end
package.preload['hs.audiodevice.watcher']   = function() return require("hs.libaudiodevicewatcher") end
package.preload['hs.battery.watcher']       = function() return require("hs.libbatterywatcher") end
package.preload['hs.bonjour.service']       = function() return require("hs.libbonjourservice") end
package.preload['hs.caffeinate.watcher']    = function() return require("hs.libcaffeinatewatcher") end
package.preload['hs.canvas.matrix']         = function() return require("hs.canvas_maxtrix") end
package.preload['hs.drawing.color']         = function() return require("hs.drawing_color") end
package.preload['hs.doc.hsdocs']            = function() return require("hs.hsdocs") end
package.preload['hs.doc.markdown']          = function() return require("hs.libmarkdown") end
package.preload['hs.fs.volume']             = function() return require("hs.libfsvolume") end
package.preload['hs.fs.xattr']              = function() return require("hs.libfsxattr") end
package.preload['hs.host.locale']           = function() return require("hs.host_locale") end
package.preload['hs.httpserver.hsminweb']   = function() return require("hs.httpserver_hsminweb") end
package.preload['hs.location.geocoder']     = function() return require("hs.location_geocoder") end
package.preload['hs.network.configuration'] = function() return require("hs.network_configuration") end
package.preload['hs.network.host']          = function() return require("hs.network_host") end
package.preload['hs.network.ping']          = function() return require("hs.network_ping") end
package.preload['hs.pasteboard.watcher']    = function() return require("hs.libpasteboardwatcher") end
package.preload['hs.screen.watcher']        = function() return require("hs.libscreenwatcher") end
package.preload['hs.socket.udp']            = function() return require("hs.libsocketudp") end
package.preload['hs.spaces.watcher']        = function() return require("hs.libspaceswatcher") end
package.preload['hs.uielement.watcher']     = function() return require("hs.libuielementwatcher") end
package.preload['hs.usb.watcher']           = function() return require("hs.libusbwatcher") end
package.preload['hs.webview.datastore']     = function() return require("hs.libwebviewdatastore") end
package.preload['hs.webview.usercontent']   = function() return require("hs.libwebviewusercontent") end
package.preload['hs.webview.toolbar']       = function() return require("hs.webview_toolbar") end
package.preload['hs.wifi.watcher']          = function() return require("hs.libwifiwatcher") end
package.preload['hs.window.filter']         = function() return require("hs.window_filter") end
package.preload['hs.window.highlight']      = function() return require("hs.window_highlight") end
package.preload['hs.window.layout']         = function() return require("hs.window_layout") end
package.preload['hs.window.switcher']       = function() return require("hs.window_switcher") end
package.preload['hs.window.tiling']         = function() return require("hs.window_tiling") end

package.preload['hs.text.http']         	= function() return require("hs.libtext_http") end
package.preload['hs.text.regex']         	= function() return require("hs.libtext_regex") end
package.preload['hs.text.utf16']         	= function() return require("hs.libtext_utf16") end

package.preload['hs.touchbar.bar']         	= function() return require("hs.libtouchbar_bar") end
package.preload['hs.touchbar.item']         = function() return require("hs.libtouchbar_item") end
package.preload['hs.touchbar.virtual']      = function() return require("hs.libtouchbar_virtual") end
package.preload['hs.touchbar.debug']      	= function() return require("hs.libtouchbar_debug") end

package.preload['hs.touchdevice.forcetouch']    = function() return require("hs.libtouchdevice_forcetouch") end
package.preload['hs.touchdevice.watcher']      	= function() return require("hs.libtouchdevice_watcher") end

return require'hs._coresetup'.setup(...)
