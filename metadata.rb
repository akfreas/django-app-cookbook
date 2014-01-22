name             'yardstick'
maintainer       'Sashimiblade'
maintainer_email 'alex@sashimiblade.com'
license          'All rights reserved'
description      'Installs/Configures yardstick'
long_description IO.read(File.join(File.dirname(__FILE__), 'README.md'))
version          '0.1.0'

%w(postgresql supervisor database python).each do |dep|
    depends dep
end
