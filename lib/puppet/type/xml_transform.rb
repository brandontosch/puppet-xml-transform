Puppet::Type.newtype(:xml_transform) do

    desc <<-EOT
        Ensures that a specified transform has been performed against a given xml
        file. The implementation uses XPath expressions to locate elements in the
        xml file and perform a specified transformation. For more information on
        XPath expressions, see here: https://www.w3schools.com/xml/xml_xpath.asp
        Multiple resources may be declared to perform any number of transforms on
        the same file. The supported transform actions are 'Remove', 'Replace',
        and 'SetAttributes'.

        For 'Remove' transforms, any elements that match the XPath expression will
        be remove from the file entirely.
        In this example, Puppet will ensure that the system.Diagnostics element
        is removed from the web.config file.

        Remove Example:
            xml_transform { 'remove_diagnostics':
                path      => 'web.config',
                transform => 'Remove',
                xpath     => '//system.diagnostics',
            }

        For 'SetAttributes' transforms, any key/value pairs specified as content
        will be set as attributes on the elements matching the XPath expression.
        In this example, Puppet will ensure that the connectionString with a name
        of SomeDB has its connectionString attribute set to the value specified in
        content.

        SetAttributes Example:
            xml_transform { 'set_connectionstring':
                path      => 'web.config',
                transform => 'SetAttributes',
                xpath     => '//connectionStrings/add[@name='SomeDB']',
                content   => {
                    connectionString => 'your connection string here',
                },
            }

        For 'Replace' transforms, the elements matching the XPath expression will
        have all of their children removed and then re-populated based on the
        elements define in content. The element_name and inner_text keys are reserved
        and used to specify the name of the xml element to create and an inner text value
        to set. The element_name key is required and the inner_text key is optional.
        In this example, Puppet will ensure that the contents of the connectionStrings
        section only contains the connection strings specified in content and nothing
        else.

        Replace Example:
            xml_transform { 'replace_connectionstrings':
                path      => 'web.config',
                transform => 'Replace',
                xpath     => '//connectionStrings',
                content   => {
                    db_one => {
                        element_name     => 'add',
                        inner_text       => 'value',
                        name             => 'db_one',
                        connectionString => 'connection string here',
                    },
                    db_two => {
                        element_name     => 'add',
                        name             => 'db_two',
                        connectionString => 'connection string here',
                    },
                },
            }
    EOT

    ensurable

    possible_transforms = [
        'Remove',
        'Replace',
        'SetAttributes',
    ]

    newparam(:name, :namevar => true) do
        desc 'An arbitrary name used as the identity of the resource.'
    end

    newparam(:path) do
        desc "The xml file to transform"
    end

    newparam(:preventformat) do
        desc "Flag indicating if post-transform formatting should be disabled."
        newvalues(:true, :false)
    end

    newparam(:transform) do
        desc "The transformation action to take: Replace, SetAttributes, Remove"
        validate do |value|
            unless possible_transforms.include? value
                raise ArgumentError , "#{value} is not a valid transform option"
            end
        end
    end

    newparam(:xpath) do
        desc "XPath query to determine target for transform"
    end

    newparam(:content) do
        desc "Hash of attributes/values to set on the target"
    end

    # Autorequire the file resource if it's being managed
    autorequire(:file) do
        self[:path]
    end

    validate do
        unless self[:path]
            raise(Puppet::Error, "path is a required attribute")
        end
        unless self[:transform]
            raise(Puppet::Error, "transform is a required attribute")
        end
        unless self[:xpath]
            raise(Puppet::Error, "xpath is a required attribute")
        end
        unless self[:content]
            unless (self[:transform].to_s == 'Remove')
                raise(Puppet::Error, "content is a required attribute when not performing a remove")
            end
        end
    end
end
