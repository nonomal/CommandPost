--- === cp.ui.RadioGroup ===
---
--- Represents an `AXRadioGroup`, providing utility methods.

local require = require

local prop                          = require "cp.prop"

local Element						= require "cp.ui.Element"
local RadioButton                   = require "cp.ui.RadioButton"

local go                            = require "cp.rx.go"
local If, Throw, WaitUntil          = go.If, go.Throw, go.WaitUntil

local insert                        = table.insert

local RadioGroup = Element:subclass("cp.ui.RadioGroup")

function RadioGroup.static.createOption(radioGroup, optionUI)
    if RadioButton.matches(optionUI) then
        return RadioButton(radioGroup, prop.THIS(optionUI))
    elseif Element.matches(optionUI) then
        return Element(radioGroup, prop.THIS(optionUI))
    end
end

--- cp.ui.RadioGroup.matches(element) -> boolean
--- Function
--- Checks if the provided `axuielement` is a RadioGroup.
---
--- Parameters:
---  * element	- The element to check.
---
--- Returns:
---  * `true` if the element is a RadioGroup.
function RadioGroup.static.matches(element)
    return Element.matches(element) and element:attributeValue("AXRole") == "AXRadioGroup"
end

--- cp.ui.RadioGroup(parent, uiFinder[, createOptionFn]) -> cp.ui.RadioGroup
--- Constructor
--- Creates a new RadioGroup.
---
--- Parameters:
---  * parent	        - The parent table.
---  * uiFinder	        - The function which will find the `axuielement` representing the RadioGroup.
---  * createOptionFn   - If provided a function that receives the `RadioGroup` and an `axuielement` for a given option within the group.
---
--- Returns:
---  * The new `RadioGroup` instance.
function RadioGroup:initialize(parent, uiFinder, createOptionFn)
    self._createOption = createOptionFn or RadioGroup.createOption
    Element.initialize(self, parent, uiFinder)
end

--- cp.ui.RadioGroup.optionCount <cp.prop: number; read-only>
--- Field
--- The number of options in the group.
function RadioGroup.lazy.prop:optionCount()
    return self.UI:mutate(
        function(original)
            local ui = original()
            return ui and #ui or 0
        end
    )
end

--- cp.ui.RadioGroup.optionsUI <cp.prop: axuielement; read-only>
--- Field
--- A `cp.prop` containing `table` of `axuielement` options available in the radio group.
---
--- Returns:
---  * The `cp.prop` of options.
function RadioGroup.lazy.prop:optionsUI()
    return self.UI:mutate(function(original)
        local ui = original()
        return ui and ui:attributeValue("AXChildren")
    end)
end

--- cp.ui.RadioGroup.options <table: cp.ui.Element; read-only>
--- Field
--- A `table` containing `cp.ui.Element` available in the radio group.
---
--- Returns:
---  * The `cp.prop` of options.
function RadioGroup.lazy.value:options()
    local optionsUI = self:optionsUI()

    if optionsUI then
        local result = {}

        for _,optionUI in ipairs(optionsUI) do
            local option = self:_createOption(optionUI)
            insert(result, option)
        end

        return result
    end
end

--- cp.ui.RadioGroup.selectedOption <cp.prop: number>
--- Field
--- The currently selected option number.
function RadioGroup.lazy.prop:selectedOption()
    return self.UI:mutate(
        function(original)
            local ui = original()
            if ui then
                local children = ui:attributeValue("AXChildren")
                for i,item in ipairs(children) do
                    if item:attributeValue("AXValue") == 1 then
                        return i
                    end
                end
            end
            return nil
        end,
        function(index, original)
            local ui = original()
            if ui then
                if index >= 1 and index <= #ui then
                    local item = ui[index]
                    if item and item:attributeValue("AXValue") ~= 1 then
                        item:doAXPress()
                        return index
                    end
                end
            end
            return nil
        end
    )
end

--- cp.ui.RadioGroup:doSelectOption(index) -> cp.rx.go.Statement<boolean>
--- Method
--- A [Statement](cp.rx.go.Statement.md) which will attempt to select the option at the specified `index`.
---
--- Parameters:
---  * index     - The index to select. Must be between 1 and [optionCount](#optionCount).
---
--- Returns:
---  * The `Statement`, which will resolve to `true` if successful or send an error if not.
function RadioGroup:doSelectOption(index)
    return If(self.isEnabled)
    :Then(function()
        local count = self:optionCount()
        if index < 1 or index > count then
            return Throw("Selected index must be between 1 and %d, but was %d", count, index)
        end
        self:selectedOption(index)

        return WaitUntil(self.selectedOption):Is(index)
        :TimeoutAfter(1000, Throw("Failed to select item %d", index))
    end)
    :Otherwise(Throw("The radio group is unavailable."))
    :Label("cp.ui.RadioGroup:doSelectOption(index)")
end

--- cp.ui.RadioGroup:nextOption() -> self
--- Method
--- Selects the next option in the group. Cycles from the last to the first option.
---
--- Parameters:
---  * None
---
--- Returns:
---  * The `RadioGroup`.
function RadioGroup:nextOption()
    local selected = self:selectedOption()
    local count = self:optionCount()
    if selected and count then
        selected = selected >= count and 1 or selected + 1
        self:selectedOption(selected)
    end
    return self
end

--- cp.ui.RadioGroup:doNextOption() -> cp.rx.go.Statement<boolean>
--- Method
--- A [Statement](cp.rx.go.Statement.md) that selects the next option in the group. Cycles from the last to the first option.
---
--- Parameters:
---  * None
---
--- Returns:
---  * The `Statement`, that resolves to `true` if successful or sends an error if not.
function RadioGroup.lazy.method:doNextOption()
    return If(self.isEnabled)
    :Then(function()
        local selected = self:selectedOption()
        local count = self:optionCount()
        selected = selected >= count and 1 or selected + 1
        return self:doSelectOption(selected)
    end)
    :Otherwise(Throw("The radio group is unavailable."))
end

--- cp.ui.RadioGroup:previousOption() -> self
--- Method
--- Selects the previous option in the group. Cycles from the first to the last item.
---
--- Parameters:
---  * None
---
--- Returns:
---  * The `RadioGroup`.
function RadioGroup:previousOption()
    local selected = self:selectedOption()
    local count = self:optionCount()
    if selected and count then
        selected = selected <= 1 and count or selected - 1
        self:selectedOption(selected)
    end
    return self
end

--- cp.ui.RadioGroup:doPreviousOption() -> cp.rx.go.Statement<boolean>
--- Method
--- A [Statement](cp.rx.go.Statement.md) that selects the previous option in the group. Cycles from the first to the last item.
---
--- Parameters:
---  * None
---
--- Returns:
---  * The `Statement`, which resolves to `true` if successful or sends an error if not..
function RadioGroup.lazy.method:doPreviousOption()
    return If(self.isEnabled)
    :Then(function()
        local selected = self:selectedOption()
        local count = self:optionCount()
        selected = selected <= 1 and count or selected - 1
        return self:doSelectOption(selected)
    end)
    :Otherwise(Throw("The radio group is unavailable."))
end

return RadioGroup
