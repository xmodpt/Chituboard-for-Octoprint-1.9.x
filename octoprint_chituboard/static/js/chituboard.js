/*
 * View model for OctoPrint-Chituboard
 *
 * Author: Vikram Sarkhel
 * License: AGPLv3
 */
$(function() {
    function ChituboardViewModel(parameters) {
        var self = this;

        // assign the injected parameters
        self.filesViewModel = parameters[0];
        self.settingsViewModel = parameters[1];
        
        // Observable for layer information
        self.layerString = ko.observable("-");

        self.onStartup = function () {
            var element = $("#state").find(".accordion-inner .progress");
            if (element.length) {
                var text = gettext("Layer");
                var tooltip = gettext("Might be inaccurate!");
                element.before(text + ": <strong title='" + tooltip + "' data-bind='text: layerString'></strong><br>");
            }
            self.retrieveData();
        };
        
        self.retrieveData = function () {
            var url = OctoPrint.getSimpleApiUrl("chituboard");
            return OctoPrint.simpleApiGet("chituboard")
                .done(function(data) {
                    if (data && data.layerString) {
                        self.layerString(data.layerString);
                    }
                })
                .fail(function() {
                    console.log("Failed to retrieve layer data from Chituboard plugin");
                });
        };
        
        // Handle custom plugin events
        self.onEventPlugin_Chituboard_Layer_Change = function () {
            self.retrieveData();
        };

        // Handle plugin messages
        self.onDataUpdaterPluginMessage = function (plugin, data) {
            if (plugin === "chituboard") {
                if (data && data.layerString) {
                    self.layerString(data.layerString);
                }
            }
        };
        
        // Enhanced file information display for SLA files
        self.filesViewModel.enableAdditionalData = function (data) {
            return data["gcodeAnalysis"] || data["analysis"] || (data["prints"] && data["prints"]["last"]);
        };

        self.filesViewModel.toggleAdditionalData = function (data) {
            var entryElement = self.filesViewModel.getEntryElement(data);
            if (!entryElement) return;

            var additionalInfo = $(".additionalInfo", entryElement);
            additionalInfo.slideToggle("fast", function () {
                $(".toggleAdditionalData i", entryElement).toggleClass(
                    "fa-chevron-down fa-chevron-up"
                );
            });
        };

        self.filesViewModel.getAdditionalData = function (data) {
            var output = "";
            
            // Check for gcode analysis first (FDM files)
            if (data["gcodeAnalysis"]) {
                if (data["gcodeAnalysis"]["dimensions"]) {
                    var dimensions = data["gcodeAnalysis"]["dimensions"];
                    output += gettext("Model size") + ": " +
                        _.sprintf("%(width).2fmm &times; %(depth).2fmm &times; %(height).2fmm", dimensions);
                    output += "<br>";
                }
                
                if (data["gcodeAnalysis"]["filament"] && typeof data["gcodeAnalysis"]["filament"] === "object") {
                    var filament = data["gcodeAnalysis"]["filament"];
                    if (_.keys(filament).length === 1) {
                        output += gettext("Filament") + ": " +
                            formatFilament(data["gcodeAnalysis"]["filament"]["tool" + 0]) + "<br>";
                    } else if (_.keys(filament).length > 1) {
                        _.each(filament, function (f, k) {
                            if (!_.startsWith(k, "tool") || !f || !f.hasOwnProperty("length") || f["length"] <= 0)
                                return;
                            output += gettext("Filament") + " (" + gettext("Tool") + " " +
                                k.substr("tool".length) + "): " + formatFilament(f) + "<br>";
                        });
                    }
                }
                
                if (data["gcodeAnalysis"]["estimatedPrintTime"]) {
                    output += gettext("Estimated print time") + ": " +
                        (self.settingsViewModel.appearance_fuzzyTimes()
                            ? formatFuzzyPrintTime(data["gcodeAnalysis"]["estimatedPrintTime"])
                            : formatDuration(data["gcodeAnalysis"]["estimatedPrintTime"])) + "<br>";
                }
                
            } else if (data["analysis"]) {
                // SLA file analysis
                if (data["analysis"]["dimensions"]) {
                    var dimensions = data["analysis"]["dimensions"];
                    output += gettext("Model size") + ": " +
                        _.sprintf("%(width).2fmm &times; %(depth).2fmm &times; %(height).2fmm", dimensions);
                    output += "<br>";
                }
                
                if (data["analysis"]["filament"] && typeof data["analysis"]["filament"] === "object") {
                    var filament = data["analysis"]["filament"];
                    if (_.keys(filament).length === 1 && filament["tool0"] && filament["tool0"]["volume"]) {
                        output += gettext("Resin volume") + ": " +
                            _.sprintf("%(volume).2f mL", {volume: filament["tool0"]["volume"]}) + "<br>";
                    }
                }
                
                if (data["analysis"]["estimatedPrintTime"]) {
                    output += gettext("Estimated print time") + ": " +
                        (self.settingsViewModel.appearance_fuzzyTimes()
                            ? formatFuzzyPrintTime(data["analysis"]["estimatedPrintTime"])
                            : formatDuration(data["analysis"]["estimatedPrintTime"])) + "<br>";
                }
                
                if (data["analysis"]["layer_count"]) {
                    output += gettext("Layer count") + ": " +
                        _.sprintf("%(layer)d", {layer: data["analysis"]["layer_count"]}) + "<br>";
                }
                
                if (data["analysis"]["layer_height_mm"]) {
                    output += gettext("Layer height") + ": " +
                        _.sprintf("%(layer).2f mm", {layer: data["analysis"]["layer_height_mm"]}) + "<br>";
                }
                
                if (data["analysis"]["printer_name"]) {
                    output += gettext("Printer name") + ": " + 
                        _.escape(data["analysis"]["printer_name"]) + "<br>";
                }
            }
            
            // Print history information
            if (data["prints"] && data["prints"]["last"]) {
                output += gettext("Last printed") + ": " +
                    formatTimeAgo(data["prints"]["last"]["date"]) + "<br>";
                if (data["prints"]["last"]["printTime"]) {
                    output += gettext("Last print time") + ": " +
                        formatDuration(data["prints"]["last"]["printTime"]) + "<br>";
                }
            }
            
            return output;
        };

        // Bind the layer string to the view model
        self.layerString = self.layerString || ko.observable("-");
    }

    // Register the view model with OctoPrint
    OCTOPRINT_VIEWMODELS.push({
        construct: ChituboardViewModel,
        dependencies: ["filesViewModel", "settingsViewModel"],
        elements: ["#files_template_machinecode"]
    });
});