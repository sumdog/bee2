#!/usr/bin/env python3

from os import environ, makedirs, path
from subprocess import call
import crypt
import random

template = """
LogFile="/usr/share/awstats/tools/logresolvemerge.pl {}/{}.log* |"
LogType=W
LogFormat=1
LogSeparator=" "
SiteDomain="{}"
HostAliases="www.{} {}"
DNSLookup=1
DirData="{}"
DirCgi="/cgi-bin"
DirIcons="/stats/icon"
AllowToUpdateStatsFromBrowser=0
AllowFullYearView=2
EnableLockForUpdate=0
DNSStaticCacheFile="dnscache.txt"
DNSLastUpdateCacheFile="dnscachelastupdate.txt"
SkipDNSLookupFor=""
AllowAccessFromWebToAuthenticatedUsersOnly=0
AllowAccessFromWebToFollowingAuthenticatedUsers=""
AllowAccessFromWebToFollowingIPAddresses=""
CreateDirDataIfNotExists=0
BuildHistoryFormat=text
BuildReportFormat=html
SaveDatabaseFilesWithPermissionsForEveryone=0
PurgeLogFile=0
ArchiveLogRecords=0
KeepBackupOfHistoricFiles=0
DefaultFile="index.php index.html"
SkipHosts=""
SkipUserAgents=""
SkipFiles=""
SkipReferrersBlackList=""
OnlyHosts=""
OnlyUserAgents=""
OnlyUsers=""
OnlyFiles=""
NotPageList="css js class gif jpg jpeg png bmp ico rss xml swf"
ValidHTTPCodes="200 304"
ValidSMTPCodes="1 250"
AuthenticatedUsersNotCaseSensitive=0
URLNotCaseSensitive=0
URLWithAnchor=0
URLQuerySeparators="?;"
URLWithQuery=0
URLWithQueryWithOnlyFollowingParameters=""
URLWithQueryWithoutFollowingParameters=""
URLReferrerWithQuery=0
WarningMessages=1
ErrorMessages=""
DebugMessages=0
NbOfLinesForCorruptedLog=50
WrapperScript=""
DecodeUA=0
MiscTrackerUrl="/js/awstats_misc_tracker.js"
UseFramesWhenCGI=1
DetailedReportsOnNewWindows=1
Expires=0
MaxRowsInHTMLOutput=1000
Lang="auto"
DirLang="./lang"
ShowMenu=1
ShowSummary=UVPHB
ShowMonthStats=UVPHB
ShowDaysOfMonthStats=VPHB
ShowDaysOfWeekStats=PHB
ShowHoursStats=PHB
ShowDomainsStats=PHB
ShowHostsStats=PHBL
ShowAuthenticatedUsers=0
ShowRobotsStats=HBL
ShowWormsStats=0
ShowEMailSenders=0
ShowEMailReceivers=0
ShowSessionsStats=1
ShowPagesStats=PBEX
ShowFileTypesStats=HB
ShowFileSizesStats=0
ShowDownloadsStats=HB
ShowOSStats=1
ShowBrowsersStats=1
ShowScreenSizeStats=0
ShowOriginStats=PH
ShowKeyphrasesStats=1
ShowKeywordsStats=1
ShowMiscStats=a
ShowHTTPErrorsStats=1
ShowSMTPErrorsStats=0
ShowClusterStats=0
AddDataArrayMonthStats=1
AddDataArrayShowDaysOfMonthStats=1
AddDataArrayShowDaysOfWeekStats=1
AddDataArrayShowHoursStats=1
IncludeInternalLinksInOriginSection=0
MaxNbOfDomain = 10
MinHitDomain  = 1
MaxNbOfHostsShown = 10
MinHitHost    = 1
MaxNbOfLoginShown = 10
MinHitLogin   = 1
MaxNbOfRobotShown = 10
MinHitRobot   = 1
MaxNbOfDownloadsShown = 10
MinHitDownloads = 1
MaxNbOfPageShown = 10
MinHitFile    = 1
MaxNbOfOsShown = 10
MinHitOs      = 1
MaxNbOfBrowsersShown = 10
MinHitBrowser = 1
MaxNbOfScreenSizesShown = 5
MinHitScreenSize = 1
MaxNbOfWindowSizesShown = 5
MinHitWindowSize = 1
MaxNbOfRefererShown = 10
MinHitRefer   = 1
MaxNbOfKeyphrasesShown = 10
MinHitKeyphrase = 1
MaxNbOfKeywordsShown = 10
MinHitKeyword = 1
MaxNbOfEMailsShown = 20
MinHitEMail   = 1
FirstDayOfWeek=1
ShowFlagLinks=""
ShowLinksOnUrl=1
UseHTTPSLinkForUrl=""
MaxLengthOfShownURL=64
HTMLHeadSection=""
HTMLEndSection=""
MetaRobot=0
Logo="awstats_logo6.png"
LogoLink="http://www.awstats.org"
BarWidth   = 260
BarHeight  = 90
StyleSheet=""
ExtraTrackedRowsLimit=500
LoadPlugin="ipv6"
"""


# Taken from https://gist.github.com/eculver/1420227
def salt():
    """Returns a string of 2 random letters"""
    letters = 'abcdefghijklmnopqrstuvwxyz' \
              'ABCDEFGHIJKLMNOPQRSTUVWXYZ' \
              '0123456789/.'
    return random.choice(letters) + random.choice(letters)


def domain_list():
    lst = []
    """convert DOMAINS env variable to a list of names"""
    for d in environ['DOMAINS'].split(' '):
        lst = lst + d.split(':')[1].split(',')
    return lst


if __name__ == '__main__':

    awdata = '/awstats/data'
    awauth = '/awstats/auth'
    awconfig = '/awstats/config'
    logs = '/weblogs'
    domains = domain_list()

    for d in [awdata, awauth, awconfig]:
        if not path.exists(d):
            print('Creating {}'.format(d))
            makedirs(d)

    with open(path.join(awauth, 'htpasswd'), 'w') as htpasswd:
        print('Setting username and password')
        htpasswd.write("{}:{}\n".format(environ['USERNAME'],
                                        crypt.crypt(environ['PASSWORD'],
                                        salt())))

    for d in domains:

        # remove port if present
        if '/' in d:
            d = d.split('/')[0]

        if path.exists(path.join(logs, '{}.log'.format(d))):
            conf = template.format(logs, d, d, d, d, awdata)
            cfile = path.join(awconfig, 'awstats.{}.conf'.format(d))
            with open(cfile, 'w') as cf:
                print('Configuring {}'.format(d))
                cf.write(conf)
            print('Generating Stats for {}'.format(d))
            call(['/usr/bin/awstats', '-config={}'.format(d)])
