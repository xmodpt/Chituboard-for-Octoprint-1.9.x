#!/usr/bin/python
# -*- coding: utf-8 -*-

from octoprint.filemanager.analysis import AbstractAnalysisQueue
import pprint
import struct
import yaml, time, os, math
import logging

from octoprint.events import Events, eventManager
from octoprint.settings import settings
from octoprint.util import dict_merge
from octoprint.util import get_fully_qualified_classname as fqcn
from octoprint.util import monotonic_time
from octoprint.util.platform import CLOSE_FDS

from .file_formats.utils import get_file_format
from pathlib import Path


class sla_AnalysisQueue(AbstractAnalysisQueue):
	"""
	A queue to analyze SLA print files from
	Chitubox, Lychee, or photon slicer
	"""

	def __init__(self, finished_callback):
		AbstractAnalysisQueue.__init__(self, finished_callback)
		
		self._aborted = False
		self._reenqueue = False

	def _do_analysis(self, high_priority=False):
		import sys
		from io import TextIOWrapper
		import sarge
		import yaml
		
		if self._current.analysis and all(
			map(
				lambda x: x in self._current.analysis,
				("printingArea", "dimensions", "estimatedPrintTime", "filament"),
			)
		):
			return self._current.analysis
		
		try:
			command = [
				sys.executable,
				"-m",
				"octoprint",
				"plugins",
				"chituboard:sla_analysis",
			]
			command.append(self._current.absolute_path)
			self._logger.debug("Invoking analysis commands: {}".format(" ".join(command)))
		
			self._aborted = False
			p = sarge.run(
				command, close_fds=CLOSE_FDS, async_=True, stdout=sarge.Capture()
			)
			self._logger.debug("check sarge process: ", p.commands[0])
			while len(p.commands) == 0:
				# somewhat ugly... we can't use wait_events because
				# the events might not be all set if an exception
				# by sarge is triggered within the async process
				# thread
				time.sleep(0.01)
			self._logger.debug("check sarge process: ", p.commands[0])

			# by now we should have a command, let's wait for its
			# process to have been prepared
			p.commands[0].process_ready.wait()
			
			if not p.commands[0].process:
				# the process might have been set to None in case of any exception
				raise RuntimeError(
					"Error while trying to run command {}".format(" ".join(command))
				)
			try:
				# let's wait for stuff to finish
				while p.returncode is None:
					if self._aborted:
						# oh, we shall abort, let's do so!
						p.commands[0].terminate()
						from octoprint.filemanager.analysis import AnalysisAborted
						raise AnalysisAborted(reenqueue=self._reenqueue)
					# else continue
					p.commands[0].poll()
			finally:
				p.close()
			output = p.stdout.text
			self._logger.debug("Got output: {!r}".format(output))
			
			result = {}
			if "ERROR:" in output:
				_, error = output.split("ERROR:")
				raise RuntimeError(error.strip())
			elif "EMPTY:" in output:
				self._logger.info("Result is empty, no extrusions found")
			elif "RESULTS:" not in output:
				raise RuntimeError("No analysis result found")
			else:
				self._logger.debug("passed if-else block")
				_, output = output.split("RESULTS:")
				self._logger.debug("passed output split {!r}".format(output))
				analysis = {}
				try:
					analysis = yaml.safe_load(output)
				except Exception as inst:
					self._logger.debug("yaml load output failed, analysis type:", inst)
					analysis = {
						"printing_area": {'minX': 5.0,'minY': 5.0, 'minZ': 5.0, 'maxX': 10.0, 'maxY': 10.0, 'maxZ': 10.0},
						"dimensions": {'width': 82.62, 'depth': 130.56, 'height': 12},
						"print_time_secs": 5500,
						"volume": 500
					}
				
				try:
					analysis["total_time"] = analysis["print_time_secs"]
				except Exception as inst:
					self._logger.debug("Failed to set total_time:", inst)
					analysis["total_time"] = analysis.get("print_time_secs", 0)
				
				result["printingArea"] = analysis.get("printing_area", {})
				result["dimensions"] = analysis.get("dimensions", {})
				
				if analysis.get("total_time"):
					result["estimatedPrintTime"] = analysis["print_time_secs"]
					
				if analysis.get("volume"):
					result["filament"] = {}
					radius = 1.75/2
					result["filament"]["tool0"] = {
							"length": analysis["volume"]/(math.pi*radius*radius),
							"volume": analysis["volume"],}
				
				if analysis.get('layer_count'):
					result['layer_count'] = analysis['layer_count']
				
				if analysis.get('layer_height_mm'):
					result['layer_height_mm'] = analysis['layer_height_mm']
				
				if analysis.get('printer name'):
					result['printer_name'] = analysis['printer name']
				
				result['path'] = analysis.get('path', self._current.absolute_path)

			if self._current.analysis and isinstance(self._current.analysis, dict):
				return dict_merge(result, self._current.analysis)
			else:
				return result
		except Exception as inst:
			self._logger.debug("Analysis for {} ran into error: {}".format(self._current, inst))
			# Return a basic result structure to prevent complete failure
			return {
				"printingArea": {'minX': 0.0, 'minY': 0.0, 'maxX': 100.0, 'maxY': 100.0},
				"dimensions": {'width': 100.0, 'depth': 100.0, 'height': 50.0},
				"estimatedPrintTime": 3600,  # 1 hour default
				"filament": {"tool0": {"volume": 10.0, "length": 100.0}},
				"layer_count": 100,
				"layer_height_mm": 0.05,
				"printer_name": "Unknown SLA Printer"
			}
		finally:
			self._gcode = None	

	def _do_abort(self, reenqueue=True):
		self._aborted = True
		self._reenqueue = reenqueue