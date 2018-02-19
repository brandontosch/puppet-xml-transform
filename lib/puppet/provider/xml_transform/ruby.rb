require 'rexml/document'
include REXML

Puppet::Type.type(:xml_transform).provide :ruby do
    desc "XML file transformer"

    def create
        # open, load and close config file (methodize this?)
        configFile = File.open(resource[:path], "r")
        doc = REXML::Document.new configFile
        configFile.close

        # get xpath query
        xpath = resource[:xpath]

        if resource[:transform].to_s == 'SetAttributes'
            # iterate through elements matching xpath query
            doc.root.elements.each(xpath) do |element|
                # set attributes (add_attribute overwrites existing or adds if absent)
                resource[:content].each { |key, value| element.add_attribute(key.to_s, value.to_s) }
            end
        elsif resource[:transform].to_s == 'Replace'
            # iterate through elements matching xpath query
            doc.root.elements.each(xpath) do |element|
                # remove all existing child elements
                element.elements.each { |e| element.delete(e)}

                # create content
                create_content(element, resource[:content])
            end
        else
            # only SetAttributes or Replace transforms should enter the create block
            raise Puppet::Error, "Invalid transform for create: '#{resource[:transform]}'"
        end

        # set default formatting to use 4 spaces
        formatSpaces = 4
        
        # override formatting if flagged
        if resource[:preventformat].to_s == 'true'
            formatSpaces = -1
        end

        # write updated xml to file
        File.open(resource[:path], "w") { |file| doc.write(file, formatSpaces) }
    end

    def destroy
        # open, load and close config file (methodize this?)
        configFile = File.open(resource[:path], "r")
        doc = REXML::Document.new configFile
        configFile.close

        # get xpath query
        xpath = resource[:xpath]

        if resource[:transform].to_s == 'Remove'
            # delete all elements matching the query
            doc.root.elements.delete(xpath)

            # set default formatting to use 4 spaces
            formatSpaces = 4
            
            # override formatting if flagged
            if resource[:preventformat].to_s == 'true'
                formatSpaces = -1
            end

            # write updated xml to file
            File.open(resource[:path], "w") { |file| doc.write(file, formatSpaces) }
        else
            # only Remove transforms should enter the destroy block
            raise Puppet::Error, "Invalid transform for destroy: '#{resource[:transform]}'"
        end
    end

    def exists?
        # open, load and close config file (methodize this?)
        configFile = File.open(resource[:path], "r")
        doc = REXML::Document.new configFile
        configFile.close

        # get xpath query
        xpath = resource[:xpath]
        # assume existance, prove otherwise below
        doesExist = true

        if resource[:transform].to_s == 'Remove'
            # check if anything matches the xpath query
            doesExist = doc.root.elements[xpath] != nil
        elsif resource[:transform].to_s == 'SetAttributes'
            # initialize var to check if xpath matches anything
            xpathHasMatch = false

            # iterate through elements matching xpath query
            doc.root.elements.each(xpath) do |element|
                # at least one match was found for xpath query
                xpathHasMatch = true
                # iterate through attributes defined in content hash
                resource[:content].each do |key, value|
                    # if a value doesn't match then the element doesn't exist in the desired state
                    if element.attributes[key.to_s] != value.to_s
                        doesExist = false
                    end
                end
            end

            if !xpathHasMatch
                raise Puppet::Error, "Unable to perform SetAttributes transform, no match for xpath: #{xpath}"
            end
        elsif resource[:transform].to_s == 'Replace'
            # generate hash for expected content
            expectedHash = expected_hash(resource[:content])
            # initialize var to check if xpath matches anything
            xpathHasMatch = false

            # iterate through elements matching xpath query
            doc.root.elements.each(xpath) do |element|
                # at least one match was found for xpath query
                xpathHasMatch = true
                # initialize actual hash as an empty string
                actualHash = ''

                # iterate through each child element
                element.elements.each do |childElement|
                    # append the hash of the child element
                    actualHash += actual_hash(childElement)
                end
                
                # check if hashes match
                if expectedHash != actualHash
                    doesExist = false
                end
            end

            if !xpathHasMatch
                raise Puppet::Error, "Unable to perform Replace transform, no match for xpath: #{xpath}"
            end
        else
            # catch for invalid transform values
            raise Puppet::Error, "Invalid transform: '#{resource[:transform]}'"
        end

        # final result of the existence check
        doesExist
    end

    private
    def create_content(parent, content)
        # iterate through element hashes defined in content
        content.each do |key, value|
            # create element with name provided by element_name value in hash
            element = parent.add_element value['element_name'].to_s

            # iterate through other values in hash
            value.each do |key, value|
                # ignore the element_name key and create others as attributes on the element
                if key.to_s == 'inner_text'
                    element.text = value.to_s
                elsif key.to_s == 'content'
                    create_content(element, value)
                elsif key.to_s != 'element_name'
                    element.add_attribute(key.to_s, value.to_s)
                end
            end
        end
    end

    # build a hash of the element as it exists in the xml
    # format of: -element_name:attrib=value:attrib=value-sibling_element_name:attrib=value>child_element_name:attrib=value
    def actual_hash(element)
         # initialize element hash with element name
        elementHash = '-' + element.name

        # add element attributes to the hash
        element.attributes.each { |a| elementHash += ":" + a[0] + "=" + a[1] }

        # add element inner text to the hash
        elementHash += ':inner_text='

        # append the text if any is specified
        if element.text != nil
            elementHash += element.text.strip
        end

        # if the element has children, append an indicator
        if element.elements.size > 0
            elementHash += '>'
        end

        # iterate through child elements
        element.elements.each do |childElement|
            # calculate and appent the child element hash
            elementHash += actual_hash(childElement)
        end

        # return final actual hash value
        elementHash
    end

    # build a hash of content defined in hiera
    # format of: -element_name:attrib=value:attrib=value-sibling_element_name:attrib=value>child_element_name:attrib=value
    def expected_hash(content)
        # initialize expected hash as an empty string
        expectedHash = ''

        # iterate through each content element
        content.each do |key, attributes|
            # initialize element hash with element name
            elementHash = attributes['element_name'].to_s
            innerText = ''
            subContent = nil

            attributes.each do |key, value|
                # if we're expecting a value for inner_text, make sure to capture as part of hash
                if key.to_s == 'inner_text'
                    innerText = value.to_s.strip
                # if there is sub-content defined, assign it to be parsed after all attributes
                elsif key.to_s == 'content'
                    subContent = value
                # ignore the element_name key since that is used as the name above
                elsif key.to_s != 'element_name'
                    elementHash += ":" + key.to_s + "=" + value.to_s
                end
            end

            # add inner text value to element hash
            elementHash += ':inner_text=' + innerText

            # if there is sub-content then parse it and add to element hash
            if subContent != nil
                elementHash += '>' + expected_hash(subContent)
            end

            # append current element hash to the expected hash
            expectedHash += '-' + elementHash
        end

        # return final expected hash value
        expectedHash
    end
end
