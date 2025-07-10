#!/usr/bin/python
# coding=utf-8

import os, sys
import logging
import re
import flask

from .sla_analyser import sla_AnalysisQueue
from .sla_printer import Sla_printer, gcode_modifier

import octoprint.plugin
import octoprint.util

from octoprint.settings import settings, default_settings

import octoprint.filemanager
import octoprint.filemanager.util
from octoprint.util import dict_merge
from octoprint.filemanager import ContentTypeMapping
from octoprint.printer.estimation import PrintTimeEstimator
from octoprint.events import eventManager, Events

regex_float_pattern = r"[-+]?[0-9]*\.?[0-9]+"
regex_positive_float_pattern = r"[+]?[0-9]*\.?[0-9]+"
regex_int_pattern = r"\d+"
REGEX_XYZ0 = re.compile(r"(?P<axis>[XYZ])(?=[XYZ]|\s|$)")
REGEX_XYZE0 = re.compile(r"(?P<axis>[XYZE])(?=[XYZE]|\s|$)")
parse_m4000 = re.compile('B:(\d+)\/(\d+)')
regex_sdPrintingByte = re.compile(r"(?P<current>[0-9]+)/(?P<total>[0-9]+)")

class Chituboard(   octoprint.plugin.SettingsPlugin,
					octoprint.plugin.SimpleApiPlugin,
					octoprint.plugin.ProgressPlugin,
					octoprint.plugin.AssetPlugin,
					octoprint.plugin.TemplatePlugin,
					octoprint.plugin.WizardPlugin,
					octoprint.plugin.StartupPlugin,
					octoprint.plugin.EventHandlerPlugin,
					octoprint.plugin.ShutdownPlugin
					):

	firmware_version = "V4.13"
	finished_print = None
	
	def __init__(self, **kwargs):
		super(Chituboard, self).__init__(**kwargs)
		self._initialized = False
		self.gcode_modifier = gcode_modifier()
		self._logged_replacement = {}
		self._logger = logging.getLogger("octoprint.plugins.Chituboard")
		self._initialized = True

	@property
	def allowed(self):
		if self._settings is None:
			return str("cbddlp, photon, ctb, fdg, pws, pw0, pwms, pwmx")
		else:
			return str(self._settings.get(["allowedExten"]))
	
	def get_extension_tree(self, *args, **kwargs):
		self._logger.debug("add Extensions: %s " % self.allowed)
		return dict(machinecode=dict(sla_bin=ContentTypeMapping(self.allowed.replace(" ", "").split(","), "application/octet-stream")))

	def get_assets(self):
		return dict(js=["js/chituboard.js"])
		
	def is_wizard_required(self):
		return True
		
	def get_wizard_version(self):
		return 1

	def on_wizard_finish(self, handled):
		self._settings.global_set(["serial", "helloCommand"], self._settings.get(["helloCommand"]))
		self._settings.global_set(["serial", "disconnectOnErrors"], False)
		self._settings.global_set(["serial", "firmwareDetection"], False)
		self._settings.global_set(["serial", "sdAlwaysAvailable"], True)
		self._settings.global_set(["serial", "neverSendChecksum"], True)
		self._settings.global_set(["serial", "capabilities", "autoreport_sdstatus"], False)
		self._settings.global_set(["serial", "capabilities", "autoreport_temp"], False)
		self._settings.global_set(["serial", "timeout", "sdStatusAutoreport"], 0)
		self._settings.global_set(["serial", "timeout", "temperatureAutoreport"], 0)
		self._settings.global_set(["serial", "baudrate"], self._settings.get(["defaultBaudRate"]))
		self._settings.global_set(["serial", "exclusive"], True)
		self._settings.global_set(["serial", "unknownCommandsNeedAck"], True)
		self._settings.save(trigger_event=True)
		self._logger.info("Octoprint-Chituboard: load settings from wizard finished ")
		handled = True
		return handled
	
	def on_api_get(self, request):
		result = "-"
		if self._printer._sliced_model_file and self._printer.is_printing():
			result = "{}/{}".format(
				self._printer.get_current_layer(),
				self._printer._sliced_model_file.layer_count
			)
		return flask.jsonify(layerString = result)
	
	def on_print_progress(self, storage, path, progress):
		if not self._printer.is_printing():
			return
		result = "-"
		if self._printer._sliced_model_file:
			result = "{}/{}".format(
				self._printer.get_current_layer(),
				self._printer._sliced_model_file.layer_count
			)
		self._plugin_manager.send_plugin_message("Chituboard",dict(layerString = result))
	
	@staticmethod
	def register_custom_events(*args, **kwargs):
		return ["layer_change"]

	def analysis_commands(self,*args, **kwargs):
		import click
		@click.command(name="sla_analysis")
		@click.argument("name", default=None)
		def sla_analysis(name):
			"""
			Analyze files created in chitubox, photon workshop and Lychee.
			Will be used in analysis queue
			"""
			import time, yaml
			from pathlib import Path
			from octoprint.util import monotonic_time
			start_time = monotonic_time()
			from .file_formats.utils import get_file_format
			if os.path.isabs(name):
				file_format = get_file_format(name)
				sliced_model_file = file_format.read(Path(name))
				click.echo("DONE:{}s".format(monotonic_time() - start_time))
				click.echo("RESULTS:")
				result = {
					"filename": sliced_model_file.filename,
					"path": name,
					"bed_size_mm": list(sliced_model_file.bed_size_mm),
					"height_mm": round(sliced_model_file.height_mm, 4),
					"layer_count": sliced_model_file.layer_count,
					"layer_height_mm": round(sliced_model_file.layer_height_mm, 4),
					"resolution": list(sliced_model_file.resolution),
					"print_time_secs": sliced_model_file.print_time_secs,
					"total_time": sliced_model_file.print_time_secs/60,
					"volume": sliced_model_file.volume,
					"printer name": sliced_model_file.printer_name,
					"printing_area": sliced_model_file.printing_area,
					"dimensions": sliced_model_file.dimensions,
					}
				click.echo(yaml.safe_dump(result,default_flow_style=False, indent=2, allow_unicode=False))
			else:
				click.echo("ERROR: not absolute path, nothing to analyse")
				sys.exit(0)	

		return [sla_analysis]

	def get_settings_defaults(self):
		return dict(
			changeSerialDefaults = False,
			allowedExten = 'cbddlp, photon, ctb, fdg, pws, pw0, pwms, pwmx',
			defaultBaudRate = 115200,
			additionalPorts = "/dev/ttyS0",
			layerImgDisplay = False,
			workAsFlashDrive = True,
			chitu_comm = False,
			photonFileEditor = False,
			useHeater = False,
			heaterTemp = 30,
			heaterTime = 20,
			resinGauge = False,
			tempSensorPrinter = None,
			tempSensorBed = None,
			helloCommand = "M4002",
			pauseCommand = "M25")
			
	def get_settings_version(self):
		return 1
		
	def on_settings_initialized(self):
		self._logger.info("Octoprint-Chituboard: load settings finished")

	def on_after_startup(self):
		self._logger.info("Octoprint-Chituboard plugin startup")

	def get_sla_analysis_factory(*args, **kwargs):
		return dict(sla_bin=sla_AnalysisQueue)

	def get_sla_printer_factory(self,components):
		"""
		Replace octoprint standard.py with new version
		"""
		self.sla_printer = Sla_printer(components["file_manager"],components["analysis_queue"],components["printer_profile_manager"])
		return self.sla_printer
		
	# Regex patterns for gcode parsing
	REGEX_XYZ0 = re.compile(r"(?P<axis>[XYZ])(?=[XYZ]|\s|$)")
	REGEX_XYZE0 = re.compile(r"(?P<axis>[XYZE])(?=[XYZE]|\s|$)")
	fix_M114 = re.compile(r"C: ")
	parse_m4000 = re.compile('B:(\d+)\/(\d+)')
	regex_sdPrintingByte = re.compile(r"(?P<current>[0-9]+)/(?P<total>[0-9]+)")
	regex_float_pattern = r"[-+]?[0-9]*\.?[0-9]+"
	regex_positive_float_pattern = r"[+]?[0-9]*\.?[0-9]+"
	regex_int_pattern = r"\d+"
	parse_M4000 = {
		"floatB": re.compile(r"(^|[^A-Za-z])[Bb]:\s*(?P<actual>%s)(\s*\/?\s*(?P<target>%s))" %
						 (regex_float_pattern, regex_float_pattern)),
		"floatD": re.compile(r"(^|[^A-Za-z])[Dd]:\s*(?P<current>%s)(\s*\/?\s*(?P<total>%s))(\s*\/?\s*(?P<pause>%s))" %
						 (regex_float_pattern, regex_float_pattern, regex_int_pattern)),
		"floatE": re.compile(r"(^|[^A-Za-z])[Ee](?P<value>%s)" % regex_float_pattern),
		"floatX": re.compile(r"(^|[^A-Za-z])[Xx]:(?P<value>%s)" % regex_float_pattern),
		"floatY": re.compile(r"(^|[^A-Za-z])[Yy]:(?P<value>%s)" % regex_float_pattern),
		"floatZ": re.compile(r"(^|[^A-Za-z])[Zz]:(?P<value>%s)" % regex_float_pattern),
		"intN": re.compile(r"(^|[^A-Za-z])[Nn](?P<value>%s)" % regex_int_pattern),
		"intS": re.compile(r"(^|[^A-Za-z])[Ss](?P<value>%s)" % regex_int_pattern),
		"intT": re.compile(r"(^|[^A-Za-z])[Tt](?P<value>%s)" % regex_int_pattern),
		}
		
	def get_gcode_receive_modifier(self, comm_instance, line, *args, **kwargs):
		line = self._rewrite_wait_to_busy(line)
		line = self._rewrite_identifier(line)
		line, end_msg = self._rewrite_print_finished(line)
		line = self._rewrite_start(line)
		line = self._rewrite_m4000_response(line)
		line = self._rewrite_m114_response(line)
		line = self._rewrite_error(line)
		if end_msg == True:
			try:
				self._printer._comm._changeState(self._printer._comm.STATE_OPERATIONAL)
				self._printer._comm._currentFile = None
			except Exception:
				self._logger.exception("Error while changing state")
		return line
	
	def _rewrite_m4000_response(self,line):
		rewritten = None
		matchB = self.parse_M4000["floatB"].search(line)
		matchD = self.parse_M4000["floatD"].search(line)
		matchX = self.parse_M4000["floatX"].search(line)
		matchY = self.parse_M4000["floatY"].search(line)
		matchZ = self.parse_M4000["floatZ"].search(line)
		
		if matchB:
			try:
				actual = matchB.group('actual')
				target = matchB.group('target')
			except Exception as inst:
				self._logger.info("Error parsing M400 response ", type(inst), inst)
			else:
				rewritten = line.replace(matchB.group(0), " T:0 /0 B:{} /{}\r\n".format(actual,target))
		if matchD and self._printer.is_pausing():
			try:
				current = int(matchD.group('current'))
				total = int(matchD.group('total'))
				paused = int(matchD.group("pause"))
			except Exception as inst:
				self._logger.info("Error parsing M400 response ", type(inst), inst)
			else:
				if paused == 1 and current > 0:
					self._printer._comm._record_pause_data = True
					self._printer._comm._changeState(self._printer._comm.STATE_PAUSED)
					Xpos = matchX.group("value")
					Ypos = matchY.group("value")
					Zpos = matchZ.group("value")
					self._logger.info("printer paused from parse M4000")
					rewritten = "ok X:{} Y:{} Z:{} E:0.000000".format(Xpos, Ypos, Zpos)
					
		if rewritten:
			self._log_to_terminal(rewritten)
			return rewritten

		return line
	
	def _rewrite_m114_response(self,line):
		if "C: X:" in line:
			rewritten = self.fix_M114.sub("", line)
			self._log_to_terminal(rewritten)
			return rewritten
		else:
			return line
		
	def _rewrite_wait_to_busy(self, line):
		if line == "wait" or line.startswith("wait"):
			self._log_replacement("wait", "wait", "echo:busy processing", only_once=True)
			return "echo:busy processing"
		else:
			return line
	
	def _rewrite_start(self, line):
		if line.startswith('ok V'):
			self.firmware_version = line[3:]
			self._log_replacement("start command",line, "ok start", only_once=True)	
			return 'ok start' + line
		return line
		
	def _rewrite_error(self, line):
		if "not printing now" in line:
			if self._printer.is_printing() or self._printer.is_finishing():
				self.finished_print = None
				self._log_replacement("Not SD printing", line, "Not SD printing", only_once=True)
				self._printer.unselect_file()
				self._printer._comm._changeState(self._printer._comm.STATE_OPERATIONAL)
				self._printer._comm._currentFile = None
				self._logger.debug("printer now operational")
			return "Not SD printing"
		else:
			return line
		
	def _rewrite_identifier(self, line):
		rewritten = None
		if "CBD make it" in line:
			rewritten = line.replace("CBD make it.", "FIRMWARE_NAME:{} PROTOCOL_VERSION:{} ".format("CBD made it", self.firmware_version))
		elif "ZWLF make it" in line:
			rewritten = line.replace("ZWLF make it", "FIRMWARE_NAME:{} PROTOCOL_VERSION:{} ".format("ZWLF made it", self.firmware_version))

		if rewritten:
			self._log_replacement("identifier", line, rewritten)
			return rewritten
		return line
		
	def _rewrite_end_msg(self,line):
		if "End read" in line:
			try:
				self._printer._comm._changeState(self._printer._comm.STATE_FINISHING)
				self._printer._comm._currentFile.done = True
				self._printer._comm._currentFile.pos = 0
				self._printer._sliced_model_file = None
				self._printer._comm._callback.on_comm_print_job_done()

			except Exception:
				self._logger.exception("Error while changing state")
			return line + "\r\n Done printing file", True
		else:	
			return line, False
			
	def _rewrite_print_finished(self,line):
		if "SD printing byte" in line:
			match = self.regex_sdPrintingByte.search(line)
			if match:
				try:
					current = int(match.group("current"))
					total = int(match.group("total"))
					self._logger.info(line)
				except Exception:
					self._logger.exception("Error while parsing SD status report")
				else:
					if current == total != 0:
						eventManager().fire(Events.PLUGIN_CHITUBOARD_LAYER_CHANGE)
						if self.finished_print == None:
							self.finished_print = 1
							self._logger.info("finished print = None")
							return line, False
						elif self.finished_print == 1:
							self._logger.info("finished print = 1")
							self._logger.info("Done printing file")
							self._log_replacement("Done printing file", line, "Done printing file", only_once=True)
							line = "Done printing file"
							self.finished_print = None
							return line, True
						elif self.finished_print == 2:
							self._logger.info("printer now operational")
							self._printer.unselect_file()
							self._printer._sliced_model_file = None
							self.finished_print == None
							return line, False
						else:
							return line, False
		return line, False
		
	def _log_replacement(self, t, orig, repl, only_once=False):
		if not only_once or not self._logged_replacement.get(t, False):
			self._logger.info("Replacing {} with {}".format(orig, repl))
			self._logged_replacement[t] = True
			if only_once:
				self._logger.info("Further replacements of this kind will be logged at DEBUG level.")
		else:
			self._logger.debug("Replacing {} with {}".format(orig, repl))
		self._log_to_terminal("{} -> {}".format(orig, repl))
		
	def _log_to_terminal(self, *lines, **kwargs):
		prefix = kwargs.pop("prefix", "Repl:")
		if self._printer:
			self._printer.log_lines(
				*list(map(lambda x: "{} {}".format(prefix, x), lines))
			)

	def get_update_information(self):
		return {
			"chituboard": {
			"displayName": "Chituboard",
			"displayVersion": self._plugin_version,
			"type": "github_commit",
			"user": "xmodpt",
			"repo": "Octoprint-Chituboard",
			"current": self._plugin_version,
			"pip": "https://github.com/xmodpt/Octoprint-Chituboard/archive/{target_version}.zip",
			}
			}

__plugin_pythoncompat__ = ">=3.9,<4"

def __plugin_load__():
	global __plugin_implementation__
	__plugin_implementation__ = Chituboard()

	global __plugin_hooks__
	__plugin_hooks__ = {
		"octoprint.plugin.softwareupdate.check_config": __plugin_implementation__.get_update_information,
		"octoprint.comm.protocol.gcode.queuing": (__plugin_implementation__.gcode_modifier.get_gcode_queuing_modifier,1),
		"octoprint.filemanager.extension_tree"  : __plugin_implementation__.get_extension_tree,
		"octoprint.filemanager.analysis.factory": __plugin_implementation__.get_sla_analysis_factory,
		"octoprint.printer.factory"			 : (__plugin_implementation__.get_sla_printer_factory,1),
		"octoprint.comm.protocol.gcode.received": (__plugin_implementation__.get_gcode_receive_modifier,1),
		"octoprint.cli.commands": __plugin_implementation__.analysis_commands,
		"octoprint.events.register_custom_events": __plugin_implementation__.register_custom_events
	}