
// Array Remove - By John Resig (MIT Licensed)
Array.prototype.remove = function (from, to) {
	var rest = this.slice((to || from) + 1 || this.length);
	this.length = from < 0 ? this.length + from : from;
	return this.push.apply(this, rest);
};



/* Remote Interface for Urban Terror
 * Oct 2009 - jgen
 */

/* Remote Interface Namespace */

var RemoteInterface = {};


// IP Address conversion functions By jgen

RemoteInterface.long2ip = function (proper_address) {
	// Convert 4-byte unsigned integer to human-readable address [IPv4 only]
	var input = parseInt(proper_address, 10);

	if (isNaN(input) || (input < 0) || (input > 4294967295)) {
		return '';
	}
	
	return	Math.floor(input / 16777216) + '.' +
		Math.floor((input % 16777216) / 65536) + '.' +
		Math.floor(((input % 16777216) % 65536) / 256) + '.' +
		Math.floor(((input % 16777216) % 65536) % 256);
};

RemoteInterface.ip2long = function (ip_address) {
	// Convert IP address string to unsigned integer [IPv4 only]
	// quick check on ip ( matches 0.0.0.0 - 999.999.999.999)
	var parts = [];

	if (ip_address.match(/^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/)) {
		parts  = ip_address.split('.');
		return ((parts[0] * 16777216) + (parts[1] * 65536) + (parts[2] * 256) + (parts[3] * 1));
	}
	return '';
};


RemoteInterface.search_panels = new Array();

RemoteInterface.init = function() {

// Configuration Options are wrapped in an object.

var config = {};

config.sUrlBase = 'interface.php';

config.bColorizeNames = false;
config.bConvertDuration = true;
config.bHideIds = true;
config.bHideNumericIps = true;
config.bHideCreationDate = true;
config.sDatetimeFormat = '%D %R';

// Menu setup
var aItemData = [
	{
		text: "Main",
		submenu: {
			id: "mainmenuitem",
			itemdata: [
				{ text: "Status", id: "mainstatus", selected: true },
				{ 
					text: "Configure",
					id: "configuremenuitem",
					submenu: {
						id: "configmenu",
						itemdata: [	{ text: "RCON password", id: 'serverpassword' },
								{ text: "Server Setup", id: 'serverconfig' },
								{ text: "Database Setup", id: 'databaseconfig' }
							]
					}
				},
				{ text: "Options", id: "options" }
			]	
		}
	},
	{
		text: "Server",
		submenu: {
			id: "servermenuitem",
			itemdata: [
				{ text: "Current Players", id: "currentplayers", helptext: "Alt + C", selected: true },
				[
					{ text: "Search by Name", id: 'searchname', helptext:"Alt + Z" },
					{ text: "Search by IP", id: 'searchip', helptext:"Alt + X" }
				]
			]
		}
	},
	{
		text: "Help",
		submenu: {
			id: "helpmenuitem",
			itemdata: [	{ text: "Help", id: "help_reference" },
					{ text: "About", id: "about" }
				]
		}
	}
];

	var oMainMenu = new YAHOO.widget.MenuBar("mainmenubar", { position: "static", lazyload: false, itemdata: aItemData });
	oMainMenu.render(document.body);

	
	
	// Generic 'Alert' Dialog
	var alert_panel = new YAHOO.widget.SimpleDialog('alert', {
		fixedcenter: true,
		visible: false,
		modal: true,
		width: '300px',
		constraintoviewport: true, 
		icon: YAHOO.widget.SimpleDialog.ICON_WARN,
	//	keylisteners: esckey,
		buttons: [
			{ text: 'OK', handler: function() { alert_panel.hide();	}, isDefault: true }
		]
	});
	alert_panel.setHeader('Alert');
	alert_panel.setBody('...');
	alert_panel.render(document.body);

	// Create a namepaced alert method
	RemoteInterface.alert = function(str) {
		alert_panel.setBody(str);
		alert_panel.cfg.setProperty('icon', YAHOO.widget.SimpleDialog.ICON_WARN);
		alert_panel.bringToTop();
		alert_panel.show();
	};
	
	
	var oAboutPanel = new YAHOO.widget.Panel("about_info", {
			width:"350px",
			height:"150px",
			visible:false,
			draggable:true,
			dragOnly:true,
			close:true,
			underlay:"Shadow",
			fixedcenter:true,
			constraintoviewport:true,
			zIndex: 5
		} );
	oAboutPanel.render(document.body);

	var oHelpPanel = new YAHOO.widget.Panel("help_panel", {
			visible:false,
			draggable:true,
			dragOnly:true,
			close:true,
			underlay:"none",
			fixedcenter:true,
			constraintoviewport:true,
			zIndex: 5
		} );
	oHelpPanel.render(document.body);

	
	var oOptionsPanel = new YAHOO.widget.Dialog("options_panel", {
			width:'360px',
			height:'275px',
			visible:false,
			draggable:true,
			dragOnly:true,
			close:true,
			underlay:"none",
			fixedcenter:true,
			constraintoviewport:true,
			zIndex: 3,
			buttons: [ { text: "Close", handler: function(o){ this.hide(); } } ]
		} );
	oOptionsPanel.render(document.body);
	
	var fLoadOptionsPanel = function() {
		var temp;
		temp = document.getElementById('config_colornames');
		temp.checked = config.bColorizeNames;
		temp = document.getElementById('config_convertduration');
		temp.checked = config.bConvertDuration;
		temp = document.getElementById('config_showplayerids');
		temp.checked = !config.bHideIds;
		temp = document.getElementById('config_shownumericips');
		temp.checked = !config.bHideNumericIps;
		temp = document.getElementById('config_showcreation');
		temp.checked = !config.bHideCreationDate;
		temp = document.getElementById('config_datetimeformat');
		temp.value = config.sDatetimeFormat;

		oOptionsPanel.show();
	};

	var fSearchRedrawTables = function() {
		for (var i =0; i < RemoteInterface.search_panels.length; i++) {
			if (RemoteInterface.search_panels[i].oSearchTable) {
				RemoteInterface.search_panels[i].oSearchTable.render();
			}
		}
	};

	var fColorNames = function() {
		config.bColorizeNames = !config.bColorizeNames;
		fSearchRedrawTables();
	};
	var fConvertDuration = function() {
		config.bConvertDuration = !config.bConvertDuration;
		fSearchRedrawTables();
	};

	// Hide() or Show() a column depending on boolean bToggle.
	// ( bToggle = true -> Column is Hidden )
	var fToggleColumn = function(bToggle, sColumnId) {
		if (sColumnId) {
			for (var i=0; i < RemoteInterface.search_panels.length; i++) {
				if (RemoteInterface.search_panels[i].oSearchTable) {
					var column1 = RemoteInterface.search_panels[i].oSearchTable.getColumn(sColumnId);
					
					if (column1) {
						if (bToggle) {
							RemoteInterface.search_panels[i].oSearchTable.hideColumn(column1);
						} else {
							RemoteInterface.search_panels[i].oSearchTable.showColumn(column1);
						}
					}
				}
			}

			for (var k=0; k < aSearchNameTableColums.length; k++) {
				if (aSearchNameTableColums[k].key == sColumnId) {
					aSearchNameTableColums[k].hidden = bToggle;
				}
			}
		}
	};

	var fShowIds = function() {
		config.bHideIds = !config.bHideIds;
		fToggleColumn(config.bHideIds, 'player_id');
		fSearchRedrawTables();
	};
	var fShowNumericIps = function() {
		config.bHideNumericIps = !config.bHideNumericIps;
		fToggleColumn(config.bHideNumericIps, 'ip');
		fSearchRedrawTables();
	};
	var fShowCreation = function() {
		config.bHideCreationDate = !config.bHideCreationDate;
		fToggleColumn(config.bHideCreationDate, 'creation');
		fSearchRedrawTables();
	};

	var fUpdateDateTime = function() {
		var temp = document.getElementById('config_datetimeformat');
		if (temp) {
			config.sDatetimeFormat = temp.value;
			fSearchRedrawTables();
		} else {
			RemoteInterface.alert("Error - missing format string.");
		}
	};

	var oApplyDateTimeBtn = new YAHOO.widget.Button({ label:"Apply", id:"config_applydatetime", container:"config_applybtn", type: "button" });
	oApplyDateTimeBtn.on("click", fUpdateDateTime);



	
	var oStatusPanel = new YAHOO.widget.Panel("status_panel", {
			width:"430px",
			visible:false,
			draggable:true,
			dragOnly:true,
			close:true,
			underlay:"shadow",
			constraintoviewport:true,
			zIndex: 2
		} );
	oStatusPanel.setHeader("Status");
	oStatusPanel.setBody("This panel contains information on the backend and the server.<br><br><div id='status_tabs'><\/div>");
	oStatusPanel.setFooter("<span id='status_refresh'><\/span>");
	oStatusPanel.render(document.body);

	var oTabView = new YAHOO.widget.TabView();
	oTabView.addTab( new YAHOO.widget.Tab({ label: 'Backend', content: '<div id="status_backend_tab"><\/div>', active: true }) );
	//oTabView.addTab( new YAHOO.widget.Tab({ label: 'Log Files', content: '<div id="backend_log_tab"><\/div>' }) );
	oTabView.addTab( new YAHOO.widget.Tab({ label: 'Server', content: '<div id="status_server_tab"><\/div>' }) );
	oTabView.appendTo("status_tabs");

	var fUpdateStatus = function() {
		var back_tab = document.getElementById('status_backend_tab');
		var serv_tab = document.getElementById('status_server_tab');
		var sQuery = config.sUrlBase + '?status';
		var tmp_str = '';
				
		var hdl_successful = function(o) {
			if (o.responseText !== undefined) {
				var status_data = '';
				try { status_data = YAHOO.lang.JSON.parse(o.responseText); }
				catch (e) { RemoteInterface.alert('An error occured while parsing the reply from the server...'); }
				
				var status = parseInt(status_data.backend.backend_status, 10);
				var msg = '';
				
				if (status !== undefined) {
					switch (status) {
						case 2:
							msg = 'Backend reports OK status.';	break;
						case 1:
							msg = 'Backend reports last shutdown was unclean.';	break;
						case 0:
							msg = 'The backend is not running.'; break;
						case -1:
							msg = 'Backend error: Could not open a socket.'; break;
						case -2:
							msg = 'Backend error: Could not connect to external address.'; break;
						case -3:
							msg = 'Backend error: Could not send message to server.'; break;
						case -4:
							msg = 'Backend error: Error recieving data from server.'; break;
						case -5:
							msg = 'Backend reports that the Server did not respond - request timed out.'; break;
						case -6:
							msg = 'Backend error: Could not close the socket.'; break;
						case -10:
							msg = 'Backend reports: Bad rcon password.'; break;
						case -11:
							msg = 'Backend reports: The server did not recognize the command.'; break;
						case -12:
							msg = 'Backend reports: No rcon password set yet.'; break;
						case -13:
							msg = 'Backend reports: Server config is missing or incorrect.'; break;
						default:
							msg = 'Unknown status value.';
					}
					
					if (status > 1) {
						back_tab.innerHTML = "<p class='status_ok'>" + msg + "<\/p>";
					} else {
						back_tab.innerHTML = "<p class='status_err'>" + msg + "<\/p>";
					}
				}
				if (status_data.server !== undefined) {
					var name = status_data.server.name;
					var map = status_data.server.current_map;
					var pw = status_data.server.rcon_pw;

					var ip = RemoteInterface.long2ip(parseInt(status_data.server.ip, 10));
					var port = parseInt(status_data.server.port, 10);
					var t_delay = parseInt(status_data.server.timeout_delay, 10);
					var t_wait = parseInt(status_data.server.timeout_wait_delay, 10);
					var timeouts = parseInt(status_data.server.timeouts, 10);
					var timeout_last = parseInt(status_data.server.timeout_last, 10);
					var timeout_Date = new Date(timeout_last * 1000);

					var srv_pw = document.getElementById('srv_rcon_pw');
					if (srv_pw && srv_pw.value == '') { srv_pw.value = pw; }

					var srv_port = document.getElementById('srv_port');
					if (srv_port && srv_port.value == '') { srv_port.value = port; }

					var srv_t_delay = document.getElementById('srv_timeout');
					if (srv_t_delay && srv_t_delay.value == '') { srv_t_delay.value = t_delay; }

					var srv_t_wait = document.getElementById('srv_timeout_wait');
					if (srv_t_wait && srv_t_wait.value == '') { srv_t_wait.value = t_wait; }

					var srv_ip = document.getElementById('srv_ip_address');
					if (srv_ip && srv_ip.value == '') { srv_ip.value = ip; }


					tmp_str = "<table class='server_info'><tbody>";
					tmp_str += "<tr><td>Server Name<\/td><td class='name'>"+ name +"<\/td><\/tr>";
					tmp_str += "<tr><td>IP Address<\/td><td>"+ ip +"<\/td><\/tr>";
					tmp_str += "<tr><td>Port<\/td><td>"+ port +"<\/td><\/tr>";
					tmp_str += "<tr><td>Map<\/td><td>"+ map +"<\/td><\/tr>";
					tmp_str += "<tr><td>Last Timeout<\/td><td>"+ timeout_Date.toGMTString() +"<\/td><\/tr>";
					tmp_str += "<\/tbody><\/table>";

					serv_tab.innerHTML = tmp_str;

					return true;
				}
			}
			RemoteInterface.alert('The server response was invalid.');
			return false;
		};
		
		var hdl_failure = function(o) {
			if (o.responseText !== undefined) {
				tmp_str = "<p class='error_title'>An error occured while communcating to the server<\/p>";
				tmp_str += "<p class='error_small'><u>Details:<\/u><br>";
				tmp_str += "Transaction id: "+ o.tId +"<br>HTTP status: "+ o.status +"<br>";
				tmp_str += "Status code message: "+ o.statusText +"<\/p>";
				back_tab.innerHTML = tmp_str;
			} else {
				RemoteInterface.alert('The server response was invalid.');
			}
		};
		
		var status_callback = {
			success: hdl_successful,
			failure: hdl_failure,
			argument: null,
			timeout: 1500		
		};
		
		var request = YAHOO.util.Connect.asyncRequest('GET', sQuery, status_callback, null);
	};
	
	var oStatusRefresh = new YAHOO.widget.Button({ label:"Refresh", id:"statusupdate", container:"status_refresh", type: "button" });
	oStatusRefresh.on("click", fUpdateStatus);
	
	
		
	// Generic 'Cancel' handler, simply hides the dialog box
	var handleGenericCancel = function(o) { this.cancel(); };

	
	var handleServerCfgApply = function(o) {
		var ans = confirm("Are you sure you want to change the server config?");
		if ( ans ) {
			this.submit();
		} else {
			this.cancel();
		}
	};
	var oServerCfgDlg = new YAHOO.widget.Dialog("server_config", {
			width: "325px",
			fixedcenter: true,
			visible:false,
			draggable:true,
			dragOnly:true,
			close:true,
			underlay:"Shadow",
			zIndex: 3,
			constraintoviewport: true,
			buttons: [ { text: "Apply", handler: handleServerCfgApply }, { text: "Cancel", handler: handleGenericCancel, isDefault: true } ]
		} );
	oServerCfgDlg.validate = function(o) {
		var data = this.getData();
		if (data.ip == "" ) {
			alert("Please enter an IP address.");
		} else if (data.port == "") {
			alert("Please enter a Port number.");
		} else if (data.timeout_delay == "") {
			alert("Please enter a timeout delay.");
		} else if (data.timeout_wait == "") {
			alert("Please enter a time to wait between timeouts.");
		} else {
			return true;
		}
		return false;
	};
	oServerCfgDlg.callback.success = function(o) {
		RemoteInterface.alert("Successfully updated the server config.");
		alert( YAHOO.lang.dump(o) );
	};
	oServerCfgDlg.callback.failure = function(o) {
		RemoteInterface.alert("Failed to update the server config.");
		alert( YAHOO.lang.dump(o) );
	};
	oServerCfgDlg.render(document.body);


	var oServerRconPwDlg = new YAHOO.widget.Dialog("server_rcon_pw", {
			width: "305px",
			fixedcenter: true,
			visible:false,
			draggable:true,
			dragOnly:true,
			close:true,
			underlay:"Shadow",
			zIndex: 3,
			constraintoviewport: true,
			buttons: [ { text: "Apply", handler:function(){this.submit();} }, { text: "Cancel", handler: handleGenericCancel, isDefault: true } ]
		} );
	oServerRconPwDlg.validate = function(o) {
		var data = this.getData();
		if (data.pw == "") {
			alert("Please enter a password.");
			return false;
		} else {
			return true;
		}
	};
	oServerRconPwDlg.callback.success = function(o) {
		RemoteInterface.alert("Updated the rcon password.");
		alert( YAHOO.lang.dump(o) );
	};
	oServerRconPwDlg.callback.failure = function(o) {
		RemoteInterface.alert("Failed to update the rcon password");
		alert( YAHOO.lang.dump(o) );
	};
	oServerRconPwDlg.render(document.body);

	
	var fSearchGarbageCollect = function() {
		for (var i =0; i < RemoteInterface.search_panels.length; i++) {
			if (RemoteInterface.search_panels[i] && RemoteInterface.search_panels[i].cfg.config.visible.value === false) {
				if (RemoteInterface.search_panels[i].oSearchTable) {
					RemoteInterface.search_panels[i].oSearchTable.destroy();
				}
				RemoteInterface.search_panels[i].destroy();
				RemoteInterface.search_panels.remove(i);
				i--;
			}
		}
	};
	

	var fNewSearchPanel = function(o) {
		if (o && o.responseText !== undefined) {
			var search_data = '';
			try { search_data = YAHOO.lang.JSON.parse(o.responseText); }
			catch (e) { RemoteInterface.alert('An error occured while parsing the reply from the server...'); }

			var id_name = "search_panel_" + o.tId;
			var id_table = "search_table_" + o.tId;
			var id_page = "search_paginator_" + o.tId;
		
			var temp = new YAHOO.widget.Panel( id_name, {
					visible:false,
					draggable:true,
					dragOnly:true,
					close:true,
					underlay:"Shadow",
					constraintoviewport:false,
					zIndex:1
				} );
			temp.setHeader("Search Results");
			temp.setBody("<div class='search_pager' id='"+ id_page +"'><\/div><div id='"+ id_table +"'><\/div>");
			temp.render( document.getElementById("search_results_container") );

			temp.oSearchPaginator = new YAHOO.widget.Paginator({
					containers: id_page,
					rowsPerPage:	15,
					rowsPerPageOptions : [10,15,25,30,40,50],
					alwaysVisible: false,
					template: '<b>{FirstPageLink} {PreviousPageLink}<\/b>{CurrentPageReport}<b>{NextPageLink} {LastPageLink}<\/b> {RowsPerPageDropdown}per page',
					firstPageLinkLabel: "<<",
					lastPageLinkLabel: ">>",
					nextPageLinkLabel: ">",
					previousPageLinkLabel: "<"
				});
			
			/* Table column configs */
			var aSearchNameTableColums = [
				{ key:"player_id", label:"ID", sortable:true, hidden: config.bHideIds },
				{ key:"name", label:"Name", formatter: formatNameColors },
				{ key:"ip", label:"IP Address", sortable:true, hidden: config.bHideNumericIps },
				{ key:"ip_text", label:"IP Address"},
				{ key:"duration", label:"Duration", formatter: formatDuration, sortable:true },
				{ key:"creation", label:"Creation", formatter: formatDateTime, hidden: config.bHideCreationDate }
			];
			var oSearchNameSchema = {
				resultsList: 'data',
				fields:[{key:'player_id', parser:'number'},
					{key:'name'},
					{key:'duration', parser:'number'},
					{key:'creation'},
					{key:'ip', parser:'number'},
					{key:'ip_text'} ],
				metaFields: { rows: 'rows' }
			};
			var aSearchIpTableColums = [
				{ key:"player_id", label:"Player ID", sortable:true, hidden: config.bHideIds },
				{ key:"ip", label:"IP", sortable:true, hidden: config.bHideNumericIps },
				{ key:"ip_text", label:"IP Address" },
				{ key:"name", label:"Player Name", formatter: formatNameColors },
				{ key:"creation", label:"Creation", formatter: formatDateTime, hidden: config.bHideCreationDate }
			];
			var oSearchIpSchema = {
				resultsList: 'data',
				fields:[{key:'player_id', parser:'number'},
					{key:'ip', parser:'number'},
					{key:'ip_text'},
					{key:'name'},
					{key:'creation'} ],
				metaFields: { rows: 'rows' }
			};

			var oSearchNameTableConfigs = {
				sortedBy: { key:'player_id', dir: YAHOO.widget.DataTable.CLASS_ASC },
				selectionMode: 'single',
				paginator: temp.oSearchPaginator
			};
			var oSearchIpTableConfigs = {
				sortedBy: { key:'ip', dir: YAHOO.widget.DataTable.CLASS_ASC },
				selectionMode: 'single',
				paginator: temp.oSearchPaginator
			};
			/* End table configs*/
			
			temp.oSearchDataSource = new YAHOO.util.LocalDataSource( o.responseText );
			temp.oSearchDataSource.responseType = YAHOO.util.DataSource.TYPE_JSON;
			
			if (search_data.type == "search_name") {
				temp.oSearchDataSource.responseSchema = oSearchNameSchema;
				temp.oSearchTable = new YAHOO.widget.DataTable( id_table, aSearchNameTableColums, temp.oSearchDataSource, oSearchNameTableConfigs);
			} else if (search_data.type == "search_ip") {
				temp.oSearchDataSource.responseSchema = oSearchIpSchema;
				temp.oSearchTable = new YAHOO.widget.DataTable( id_table, aSearchIpTableColums, temp.oSearchDataSource, oSearchIpTableConfigs);
			} else {
				RemoteInterface.alert('The server response is the wrong type.');
			}
				
			RemoteInterface.search_panels.push(temp);
			temp.show();
		} else {
			RemoteInterface.alert('The server response was invalid.');
		}
		fSearchGarbageCollect();
	};

	/* Functions used by the Search Panel Tables */
	var formatNameColors = function(elCell, oRecord, oColumn, oData) {
		var list = oData;
		if (config.bColorizeNames) {
			list = list.replace(/\^0/g, "<font color='#000000'>");
			list = list.replace(/\^1/g, "<font color='#FF0000'>");
			list = list.replace(/\^2/g, "<font color='#00FF00'>");
			list = list.replace(/\^3/g, "<font color='#FFFF00'>");
			list = list.replace(/\^4/g, "<font color='#0000FF'>");
			list = list.replace(/\^5/g, "<font color='#00FFFF'>");
			list = list.replace(/\^6/g, "<font color='#FF00FF'>");
			list = list.replace(/\^7/g, "<font color='#FFFFFF'>");
		}
		elCell.innerHTML = list;
	};
	var formatDuration = function(elCell, oRecord, oColumn, oData) {
		if (config.bConvertDuration) {
			var days, hr, min, sec;

			if (oData > 86400) {
				days = Math.floor(oData / 86400);
				hr = Math.floor((oData % 86400) / 3600);
				min = Math.floor((oData % 3600) / 60);
				sec = oData % 60;
			
				elCell.innerHTML = days + ' d ' + hr + ' hr ' + min + ' min ' + sec + ' sec';
			} else if (oData > 3600) {
				hr = Math.floor(oData / 3600);
				min = Math.floor((oData % 3600) / 60);
				sec = oData % 60;
			
				elCell.innerHTML = hr + ' hr ' + min + ' min ' + sec + ' sec';
			} else if (oData > 60) {
				min = Math.floor(oData / 60);
				sec = oData % 60;
				
				elCell.innerHTML = min + ' min ' + sec + ' sec';
			} else {
				elCell.innerHTML = oData + ' sec';
			}
		} else {
			elCell.innerHTML = oData;
		}
	};
	var formatDateTime = function(elCell, oRecord, oColumn, oData) {
		if (oData) {
			var oDate = new Date(oData);
			elCell.innerHTML = YAHOO.util.Date.format( oDate, {format: config.sDatetimeFormat} );
		} else {
			elCell.innerHTML = 'No Data';
		}
	};
	var formatList = function(elCell, oRecord, oColumn, oData) {
		if (oData) {
			var str = oData.toString();
			var list = str.split(',');
			str = '';
			for (var i=0; i < list.length; i++) {
				str = str + list[i] + ', ';
			}
			elCell.innerHTML = str.substring(0, str.length - 2);
		}
	};

	var formatNameList = function(elCell, oRecord, oColumn, oData) {
		var list = oData.slice(1, oData.length - 1);
		if (bColorizeNames) {
			//list = '<span style="background-color: #AAAAAA;">' + list;
			list = list.replace(/\^0/g, "<font color='#000000'>");
			list = list.replace(/","/g, "<font color='#000000'>\",\"");
			list = list.replace(/"$/,   "<font color='#000000'>\"");
			list = list.replace(/\^1/g, "<font color='#FF0000'>");
			list = list.replace(/\^2/g, "<font color='#00FF00'>");
			list = list.replace(/\^3/g, "<font color='#FFFF00'>");
			list = list.replace(/\^4/g, "<font color='#0000FF'>");
			list = list.replace(/\^5/g, "<font color='#00FFFF'>");
			list = list.replace(/\^6/g, "<font color='#FF00FF'>");
			list = list.replace(/\^7/g, "<font color='#FFFFFF'>");
			//list = list + '<\/span>';
		}
		elCell.innerHTML = list;
	};
	/* End of Search Panel Functions */


	var msgSearchError = function() {
		RemoteInterface.alert("There was an error preforming the search.");
	};
	
	var handleSubmitName = function(o) { this.submit(); };
	var oSearchNameDlg = new YAHOO.widget.Dialog("search_name",
		{	width: "350px",
			visible: false,
			draggable: true,
			dragOnly: true,
			close: true,
			fixedcenter:true,
			underlay: "none",
			zIndex: 3,
			constraintoviewport: true,
			buttons: [ { text: "Search", handler: handleSubmitName, isDefault: true }, { text: "Close", handler: handleGenericCancel } ]
		} );
	oSearchNameDlg.validate = function(o) {
		var data = this.getData();
		if (data && data.name_text == "") {
			alert("Please enter some text to search for..");
			return false;
		} else {
			return true;
		}
	};
	oSearchNameDlg.callback.success = fNewSearchPanel;
	oSearchNameDlg.callback.failure = msgSearchError;
	oSearchNameDlg.render(document.body);


	var handleSubmitIp = function(o) { this.submit(); };
	var oSearchIpDlg = new YAHOO.widget.Dialog("search_ip", {
			width: "275px",
			visible: false,
			draggable: true,
			dragOnly: true,
			close: true,
			fixedcenter:true,
			underlay: "none",
			zIndex: 3,
			constraintoviewport: true,
			buttons: [ { text:"Search", handler: handleSubmitIp }, { text:"Close", handler: handleGenericCancel, isDefault: true } ]
		} );
	oSearchIpDlg.validate = function(o) {
		var data = this.getData();
		if (data && data.ip_text == "") {
			alert("Please enter something to search for..");
			return false;
		} else {
			return true;
		}
	};
	oSearchIpDlg.callback.success = fNewSearchPanel;
	oSearchIpDlg.callback.failure = msgSearchError;
	oSearchIpDlg.render(document.body);


	var oCurrentPlayers = new YAHOO.widget.Panel("current_players", {
	/*		width:"700px",
			height:"400px", */
			visible:false,
			draggable:true,
			dragOnly:true,
			close:true,
			underlay:"none",
			fixedcenter:true,
			constraintoviewport:true,
			zIndex: -1
		} );
	oCurrentPlayers.setBody("<div id='player_table'><\/div>");
	oCurrentPlayers.render(document.body);
	
	var aPlayerTableColumns = [
		{ key:"slot_num", label:"Slot", formatter:"number", sortable:true },
		{ key:"score", label:"Score", formatter:"number", sortable:true },
		{ key:"ping", label:"Ping", formatter:"number", sortable:true },
		{ key:"name", label:"Player Name", formatter: formatNameColors },
		{ key:"ip", label:"IP Address" },
		{ key:"qport", label:"q Port", formatter:"number", sortable:true },
		{ key:"rate", label:"Rate", formatter:"number", sortable:true }
	];

	var oPlayerDataSource = new YAHOO.util.DataSource( config.sUrlBase + '?players' );
	oPlayerDataSource.responseType = YAHOO.util.DataSource.TYPE_JSON;
	oPlayerDataSource.responseSchema = {
		resultsList: 'data',
		fields:[{key:'slot_num', parser:'number'},
			{key:'score', parser:'number'},
			{key:'ping', parser:'number'},
			{key:'name'},
			{key:'ip', parser: RemoteInterface.long2ip },
			{key:'qport', parser:'number'},
			{key:'rate', parser:'number'} ],
		metaFields: { rows: 'rows' }
	};

	var oPlayerTableConfigs = {
		sortedBy:{key:'slot_num',dir:'asc'},
		selectionMode: 'single'
	};
	
	var oPlayerTable = new YAHOO.widget.DataTable("player_table", aPlayerTableColumns, oPlayerDataSource, oPlayerTableConfigs);
	
	var PlayerDataCallback = {
		success: oPlayerTable.onDataReturnInitializeTable,
		failure: oPlayerTable.onDataReturnInitializeTable, /* function() { alert("Error getting player list from database backend."); }, */
		scope: oPlayerTable
	};
	
	oPlayerDataSource.setInterval(4000, null, PlayerDataCallback);
	// TODO: If Possible: only poll backend if the playerlist panel is visible...

	// Listeners for the MenuBar
	YAHOO.util.Event.addListener("about", "click", oAboutPanel.show, oAboutPanel, true);
	YAHOO.util.Event.addListener("help_reference", "click", oHelpPanel.show, oHelpPanel, true);
	YAHOO.util.Event.addListener("options", "click", fLoadOptionsPanel);
	YAHOO.util.Event.addListener("serverpassword", "click", oServerRconPwDlg.show, oServerRconPwDlg, true);
	YAHOO.util.Event.addListener("currentplayers", "click", oCurrentPlayers.show, oCurrentPlayers, true);
	YAHOO.util.Event.addListener("mainstatus", "click", oStatusPanel.show, oStatusPanel, true);
	YAHOO.util.Event.addListener("serverconfig", "click", oServerCfgDlg.show, oServerCfgDlg, true);
	YAHOO.util.Event.addListener("searchname", "click", oSearchNameDlg.show, oSearchNameDlg, true);
	YAHOO.util.Event.addListener("searchip", "click", oSearchIpDlg.show, oSearchIpDlg, true);
	
	// Listeners for Options Panel
	YAHOO.util.Event.addListener("config_colornames", "click", fColorNames);
	YAHOO.util.Event.addListener("config_convertduration", "click", fConvertDuration);
	YAHOO.util.Event.addListener("config_showplayerids", "click", fShowIds);
	YAHOO.util.Event.addListener("config_shownumericips", "click", fShowNumericIps);
	YAHOO.util.Event.addListener("config_showcreation", "click", fShowCreation);

	// Listeners for Keyboard shortcuts
	var key1 = new YAHOO.util.KeyListener(document, { alt:true, keys:90}, {fn:oSearchNameDlg.show, scope:oSearchNameDlg, correctScope:true});
	var key2 = new YAHOO.util.KeyListener(document, { alt:true, keys:88}, {fn:oSearchIpDlg.show, scope:oSearchIpDlg, correctScope:true});
	var key3 = new YAHOO.util.KeyListener(document, { alt:true, keys:67}, {fn:oCurrentPlayers.show, scope:oCurrentPlayers, correctScope:true});

	key1.enable();
	key2.enable();
	key3.enable();
};



/*** Initialize and render when the DOM is ready to be scripted. ***/
YAHOO.util.Event.onDOMReady( RemoteInterface.init );


