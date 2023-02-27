#!/usr/bin/env python
import gi

gi.require_version('Gtk', '3.0')
from gi.repository.Gtk import ListStore
from gi.repository import Gtk
from gi.repository import Gdk
from gi.repository import GLib
from bs4 import BeautifulSoup as Soup
from bs4 import SoupStrainer as Strainer
from datetime import datetime
from logging import handlers
import getopt
import logging
import numpy as np
import os
import re
import requests
import subprocess
import sys
import threading

# Constants
TORRENT_CLIENT = "/usr/bin/deluge"
DEFAULT_ENGINE = "pb"
BOLD = "\033[1m"
ITALIC = "\033[3m"
WHITE = "\033[0;37m"
RED = "\033[0;31m"
RESET = "\033[0m"
SUPPORTED_ENGINES = {
    "pb": "The Pirate Bay",
    "lime": "Lime Torrents",
    "eztv": "Eztv Torrents"
}
SCRIPT = os.path.basename(sys.argv[0])

USAGE_TXT = """
Usage: {} [-h] [-e <ENGINE>] [<TITLE>]

Options:-h: help
        -e: <ENGINE>

DESC: Search engine for {}
      Enter <TITLE> via gui or on the command line

SUPPORTED ENGINES:
    pb   : The Pirate Bay (default)
    lime : Lime Torrents
    eztv : Eztv Torrents

""".format(SCRIPT, os.path.basename(TORRENT_CLIENT).title())

# Globals
return_val = None
torrent_list = []

# Functions
def usage():
    print(USAGE_TXT)
    sys.exit(0)


def get_cmdline():
    opts, args = [], []
    set_opts = {"engine": DEFAULT_ENGINE}

    try:
        opts, args = getopt.getopt(sys.argv[1:], "he:", ["engine="])
    except getopt.GetoptError as err:
        print(err)  # option not recognized
        usage()

    for o, a in opts:
        if o in ("-h", "--help"):
            usage()
        elif o in ("-e", "--engine"):
            set_opts = {"engine": a}
        else:
            assert False, "unhandled option"

    return set_opts, args


def handle_exception(exc_type, exc_value, exc_traceback):
    if issubclass(exc_type, KeyboardInterrupt):
        sys.__excepthook__(exc_type, exc_value, exc_traceback)
        return

    logger.error("Uncaught exception", exc_info=(exc_type, exc_value, exc_traceback))


def init_logging():
    sys_logger = logging.getLogger(__name__)
    sys_logger.setLevel(logging.WARN)

    handler = logging.handlers.SysLogHandler(address='/dev/log')
    sys_logger.addHandler(handler)

    return sys_logger


def get_model(site):
    engine_models = {
        "pb": "PbModel",
        "lime": "LimeModel",
        "eztv": "EztvModel"
    }
    return engine_models[site]

def model_query(model, search_term):
    return_val, torrent_list = model.get_list(search_term)
    return return_val, torrent_list


# Classes and Methods
class SearchWin(Gtk.Window):
    def __init__(self, engine_key=None, search_term=None, set_active=None):

        Gtk.Window.__init__(self)
        self.engine_key = engine_key
        self.search_term = search_term
        self.set_active = set_active
        self.active_search = None
        self.return_val = None
        self.torrent_list = None

        if self.engine_key is None:
            self.engine_key = DEFAULT_ENGINE

        self.initial_query = False if self.search_term is None else True

        self.model = None
        self.set_model(self.engine_key)

        # Window setup
        self.set_border_width(10)
        self.set_position(Gtk.WindowPosition.CENTER_ALWAYS)
        self.set_keep_above(True)
        self.set_resizable(False)
        self.connect('delete-event', self.on_quit)  # window closed

        # Create history file if it doesn't exist
        self.hist_path = os.environ['HOME'] + r'/.ts'
        try:
            if not os.path.exists(os.path.dirname(self.hist_path)):
                os.mkdir(os.path.dirname(self.hist_path))
        except OSError as err:
            print(err)

        self.hist_file = 'hist.txt'
        self.hist_file_path = self.hist_path + '/' + self.hist_file
        self.new_hist()

        # Create the history liststore
        self.hist_store = Gtk.ListStore(int, str)

        # Add history 
        self.ndx = 1
        with open(self.hist_file_path, "r") as fh:
            for line in fh:
                self.hist_store.append([self.ndx, line.strip()])
                self.ndx += 1

        # Define the ComboBox for liststore
        self.hist_combo = Gtk.ComboBox.new_with_model_and_entry(self.hist_store)
        self.hist_combo.set_entry_text_column(1)
        if self.set_active is not None:
            self.hist_combo.set_active(self.set_active)
        self.connect("key-release-event", self.on_enter, self.hist_combo)  # engage the enter key

        # Define the buttons and handlers
        buttons = list()

        button = Gtk.Button(label="Search")
        button.connect("clicked", self.on_search, self.hist_combo)
        buttons.append(button)

        button = Gtk.Button(label="Engine")
        button.connect("clicked", self.on_engine)
        buttons.append(button)

        button = Gtk.Button(label="Clear History")
        button.connect("clicked", self.on_clear, self.hist_combo)
        buttons.append(button)

        button = Gtk.Button(label="Quit")
        button.connect("clicked", self.on_quit)
        buttons.append(button)

        # prompt - indicates unsuccessful query
        self.prompt = Gtk.Label()
        self.prompt.set_xalign(0.0)  # left align label
        self.set_prompt(True)

        # Create a grid container
        grid = Gtk.Grid()
        grid.set_column_homogeneous(True)
        grid.set_row_homogeneous(True)
        self.add(grid)  # add grid to window

        self.spinner = Gtk.Spinner()

        # Set up the grid
        grid.attach(self.prompt, 0, 0, 2, 1)  # row, col, width, height
        grid.attach_next_to(self.spinner, self.prompt, Gtk.PositionType.RIGHT, 1, 1)
        grid.attach_next_to(self.hist_combo, self.prompt, Gtk.PositionType.BOTTOM, 5, 1)
        grid.attach_next_to(buttons[0], self.hist_combo, Gtk.PositionType.BOTTOM, 1, 1)  # first button
        for i, button in enumerate(buttons[1:]):
            grid.attach_next_to(button, buttons[i], Gtk.PositionType.RIGHT, 1, 1)  # remaining buttons

        self.show_all()

        if self.initial_query is True:
            self.run_query()
            self.destroy()
            return

        Gtk.main()

    def run_query(self):
        while Gtk.events_pending():
            Gtk.main_iteration()

        self.do_threaded_query()

    def set_model(self, key):
        self.engine_key = key
        self.model = eval(get_model(key))
        self.set_title("Torrent Search - " + SUPPORTED_ENGINES[key])
        self.torrent_list = None

    def set_prompt(self, state):
        if state is True:
            prompt_text = "Enter search phrase"
            self.prompt.set_label(prompt_text)
            self.prompt.set_markup('<span foreground="white">' + '<big>' + prompt_text + '</big></span>')
        else:
            prompt_text = "No results"
            self.prompt.set_label(prompt_text)
            self.prompt.set_markup('<span foreground="red">' + '<big>' + prompt_text + '</big></span>')

    def store_manager(self, line, combo):
        tree_iter = combo.get_active_iter()
        if tree_iter is None:
            self.ndx += 1
            self.hist_store.append([self.ndx, line.strip()])
            self.file_manager(line)

    def file_manager(self, line):
        line = line + "\n"
        with open(self.hist_file_path, "a") as fh:
            fh.write(line)

    def new_hist(self):
        os.umask(0)
        os.open(
            self.hist_file_path,
            flags=(os.O_RDWR  # access mode: write only
                   | os.O_CREAT  # create if not exists
                   ),
            mode=0o644
        )

    def on_enter(self, widget, event, combo):
        if event.string == '\r':
            entry = combo.get_child()
            self.search_term = entry.get_text()

            if len(self.search_term) == 0:
                combo.grab_focus()
                return

            self.store_manager(self.search_term, combo)
            self.active_search = combo.get_active()
            self.do_threaded_query()
        else:
            return

    def on_search(self, button, combo):
        self.active_search = combo.get_active()
        entry = combo.get_child()
        self.search_term = entry.get_text()

        if len(self.search_term) == 0:
            combo.grab_focus()
            return

        self.do_threaded_query()

    def do_threaded_query(self):
        self.spinner.start()
        thread = threading.Thread(target=self.do_query)
        thread.daemon = True
        thread.start()

    def do_query(self):
        global torrent_list
        global return_val

        self.return_val, self.torrent_list = model_query(self.model, self.search_term)

        GLib.idle_add(self.thread_complete)

    def thread_complete(self):
        self.spinner.stop()

        if self.return_val == 1:  # engine returned nothing
            self.set_prompt(False)
            self.hist_combo.grab_focus()
            return
        else:
            self.set_prompt(True)

        if self.initial_query is True:
            return

        self.destroy()
        Gtk.main_quit()

    def on_engine(self, button):
        context_menu = Gtk.Menu()
        for key, value in SUPPORTED_ENGINES.items():
            if key == self.engine_key:
                continue
            cm_item = Gtk.MenuItem(label=value)
            cm_item.connect("activate", self.on_popup, key)
            context_menu.add(cm_item)

        context_menu.show_all()
        context_menu.popup(None, None, None, None, 1, 1)

    def on_popup(self, menu, key):
        self.set_model(key)

    def on_clear(self, button, combo):
        os.remove(self.hist_file_path)
        self.new_hist()
        self.hist_store.clear()
        combo.get_child().set_text("")
        combo.grab_focus()

    def on_quit(self, button, data=None):
        Gtk.main_quit()
        sys.exit(0)


class ListingWin(Gtk.Window):
    torrent_list_store: ListStore

    def __init__(self, torrent_list, engine_key):
        self.torrent_list = torrent_list
        self.engine = engine_key

        Gtk.Window.__init__(self, title="Torrent Listing - " + SUPPORTED_ENGINES[self.engine])

        self.new_search = False
        self.new_engine = False
        self.download = False
        self.popup_entry = None
        self.selected_titles = None

        # Window setup
        self.set_border_width(10)
        self.set_default_size(1000, 400)
        self.set_position(Gtk.WindowPosition.CENTER_ALWAYS)
        self.set_keep_above(True)
        self.connect('delete-event', self.on_quit)

        # Post-process torrent_list: Create dictionary (fields 1,5) for magnet[title] lookup
        titles, magnets = [], []

        for L in self.torrent_list:
            titles.append(L[0])
            magnets.append(L[-1])

        # Stash the magnets
        self.magnet_dict = dict(zip(titles, magnets))

        # Post-process torrent_list: Create listStore (fields 1-5) without magnets
        post_list = np.array(self.torrent_list)
        store_data = post_list[:, :5].tolist()  # numpy syntax for grabbing fields 1-5 from each row

        # Create the ListStore model: "Title", "Date", "Seeds", "Leeches", "Size"
        self.torrent_list_store = Gtk.ListStore(str, str, int, int, str, float)

        for torrent_ref in store_data:
            f1 = torrent_ref[0]  # title
            f2 = torrent_ref[1]  # Date
            f3 = int(torrent_ref[2])  # Seeds
            f4 = int(torrent_ref[3])  # Leeches
            f5 = torrent_ref[4]  # Size
            #  sort MB, GB, and KiB
            if "N/A" in f5:
                s5 = 0
            elif "G" in f5:
                c5 = f5.replace('G', '')
                if self.is_number(c5):
                    n1 = float(c5)
                    n2 = float(1024)
                    s5 = n1 * n2
                else:
                    s5 = 0
            elif "M" in f5:
                c5 = f5.replace('M', '')
                if self.is_number(c5):
                    s5 = float(c5)
                else:
                    s5 = 0
            elif "K" in f5:
                c5 = f5.replace('KiB', '')
                if self.is_number(c5):
                    s5 = float(c5)
                else:
                    s5 = 0
            else:
                s5 = re.sub('[^0-9\.]', '', f5)
                if not self.is_number(s5):
                    s5 = 0

            row = [f1, f2, f3, f4, f5, s5]
            self.torrent_list_store.append(row)

        # Create the treeview
        self.treeview = Gtk.TreeView()
        self.treeview.set_model(self.torrent_list_store)  # pass the model
        self.treeview.connect("button_press_event", self.show_context_menu)  # right click - context menu
        self.treeview.connect("row-activated", self.row_active)  # double click - submit row
        self.treeview.get_selection().set_mode(Gtk.SelectionMode.MULTIPLE)  # multiple row selection
        self.treeview.set_cursor(0)  # highlight first row

        # Add columns & headers
        renderer_1 = Gtk.CellRendererText()
        renderer_2 = Gtk.CellRendererText()
        renderer_2.set_property("xalign", 1)

        column = Gtk.TreeViewColumn("Title", renderer_1, text=0)
        column.set_sort_column_id(0)
        self.treeview.append_column(column)

        column = Gtk.TreeViewColumn("Date", renderer_2, text=1)
        column.set_sort_column_id(1)
        self.treeview.append_column(column)

        column = Gtk.TreeViewColumn("Seeds", renderer_2, text=2)
        column.set_sort_column_id(2)
        self.treeview.append_column(column)

        column = Gtk.TreeViewColumn("Leeches", renderer_2, text=3)
        column.set_sort_column_id(3)
        self.treeview.append_column(column)

        #  Display field for Size (f4), sort field for Size (s5)
        column = Gtk.TreeViewColumn("Size", renderer_2, text=4)
        column.set_sort_column_id(5)
        self.treeview.append_column(column)

        # Define the buttons and handlers
        self.entry = Gtk.Entry()
        self.entry.connect("activate", self.on_download)  # enables enter key

        self.buttons = list()

        button = Gtk.Button(label="Download")
        button.connect("clicked", self.on_download)
        self.buttons.append(button)

        button = Gtk.Button(label="Search")
        button.connect("clicked", self.on_search)
        self.buttons.append(button)

        button = Gtk.Button(label="Quit")
        button.connect("clicked", self.on_quit)
        self.buttons.append(button)

        # Create a scrollable window
        self.scrollable_treeList = Gtk.ScrolledWindow()
        self.scrollable_treeList.set_vexpand(True)

        # Add the treeview to the scrollable window
        self.scrollable_treeList.add(self.treeview)

        # Create a grid container
        self.grid = Gtk.Grid()
        self.grid.set_column_homogeneous(True)
        self.grid.set_row_homogeneous(True)
        self.add(self.grid)  # add the grid to the window

        # Add the scrollable window to the grid
        self.grid.attach(self.scrollable_treeList, 0, 0, 8, 10)  # row,col,(h,w cells)

        # Add the buttons to the grid
        self.grid.attach_next_to(self.buttons[0], self.scrollable_treeList, Gtk.PositionType.BOTTOM, 1, 1)
        for i, button in enumerate(self.buttons[1:]):
            self.grid.attach_next_to(button, self.buttons[i], Gtk.PositionType.RIGHT, 1, 1)

        self.show_all()
        Gtk.main()

    def is_number(self, str_int):
        try:
            float(str_int)
            return True
        except ValueError:
            return False

    # Context menu to select another engine
    def show_context_menu(self, widget, event):
        if event.type == Gdk.EventType.BUTTON_PRESS and event.button == 3:
            context_menu = Gtk.Menu()
            for key, value in SUPPORTED_ENGINES.items():
                if key == self.engine:
                    continue
                cm_item = Gtk.MenuItem(label=value)
                cm_item.connect("activate", self.on_popup)
                context_menu.add(cm_item)

            context_menu.attach_to_widget(self, None)
            context_menu.show_all()
            context_menu.popup(None, None, None, None, event.button, event.time)

    def on_popup(self, popup):
        entry = popup.get_child()
        text = entry.get_text()
        for key, value in SUPPORTED_ENGINES.items():
            if value == text:
                self.popup_entry = key
                self.new_engine = True
                break

        Gtk.main_quit()

    # If double-click on row, download and exit
    def row_active(self, tv, col, tv_col):
        self.on_download(self)

    def on_download(self, button):
        # Retrieve selected titles from ListStore
        self.selected_titles = []

        selection = self.treeview.get_selection()
        (self.torrent_list_store, tree_iterator) = selection.get_selected_rows()

        for path in tree_iterator:
            path_iter = self.torrent_list_store.get_iter(path)
            if path_iter is not None:
                self.selected_titles.append(
                    self.torrent_list_store.get_value(path_iter, 0))

            self.download = True
        Gtk.main_quit()

    def on_search(self, button):
        self.new_search = True
        Gtk.main_quit()

    def on_quit(self, button, args=None):
        Gtk.main_quit()
        sys.exit(0)


def filter_sz_age(tag):
    if tag.find('a') is not None:  # eliminate <td containing <a tags
        return False
    return tag.name == 'td' and len(tag.attrs) == 2 and (
            tag.attrs["class"] == ["forum_thread_post"] and tag.attrs["align"] == 'center')


class EztvModel:
    myUrl = "https://eztv.re"

    def get_list(search_phrase):
        # Prep the url
        current_search = EztvModel.myUrl + '/search/' + search_phrase.replace(' ', '%20')

        # Pull the page
        page = requests.get(current_search)

        # Isolate the relevant data
        detail = Strainer('tr', {'class': 'forum_header_border'})
        soup = Soup(page.content.decode('ISO-8859-1'), features="html.parser", parse_only=detail)

        tds = soup.find_all("td", attrs={"class": "forum_thread_post", "align": "center"})

        #  Eliminate doubled magnet links; only take the first
        a_tags = []
        for td in tds:
            tags = td.find_all("a", attrs={"class": "magnet"})
            if len(tags) == 0:
                continue

            a_tags.append(tags[0])

        links = [a["href"] for a in a_tags]
        raw_titles = [a["title"] for a in a_tags]

        # Non result; early exit
        # Eztv will always return a list even for non matches
        bad_query = True
        for raw_title in raw_titles:
            if search_phrase.lower() in raw_title.lower():
                bad_query = False
                break

        if bad_query:
            return 1, None

        titles = []
        for raw_title in raw_titles:
            raw_title = raw_title.replace('Magnet Link', '')  # kill link desc in title
            raw_title = re.sub('\[eztv\]', '', raw_title)  # kill eztv tag in title
            raw_title = re.sub('\(.*\)', '', raw_title)  # kill size in title
            titles.append(raw_title)

        sz_age = []
        for sag in soup.find_all(filter_sz_age):
            sz_age.append(str(sag.get_text()).strip())

        # Assign alternating rows
        ages, raw_sizes = [], []
        for age in range(len(sz_age)):
            if (age % 2) == 0:
                raw_sizes.append(sz_age[age])
            else:
                ages.append(sz_age[age])

        # Normalize size info
        sizes = []
        for size in raw_sizes:
            file_size = size
            file_size = file_size.replace('GB', 'G')
            file_size = file_size.replace('MB', 'M')
            file_size = file_size.replace('KB', 'K')
            sizes.append(file_size)

        seeds_raw = soup.find_all("td", attrs={"align": "center", "class": "forum_thread_post_end"})
        seeds_raw = [str(sd.get_text()).strip() for sd in seeds_raw]

        # Filter non integer data
        seeds = []
        for seed_raw in seeds_raw:
            if seed_raw.isdigit():
                seed = seed_raw
            else:
                seed = 0
            seeds.append(seed)

        # No leech info provided in this model
        leeches = ["0" for sd in seeds_raw]

        # Return listStore data and provide an extra payload of link data
        torrent_list = []
        for ndx in range(0, len(titles)):
            torrent_list.append(
                (titles[ndx],
                 ages[ndx],
                 seeds[ndx],
                 leeches[ndx],
                 sizes[ndx],
                 links[ndx]))

        return 0, torrent_list


EztvModel.get_list = staticmethod(EztvModel.get_list)


class LimeModel:
    myUrl = "https://www.limetorrents.lol"

    def get_list(search_phrase):
        # Prep the url
        current_search = LimeModel.myUrl + '/search/all/' + search_phrase.replace(' ', '%20')

        # Pull the page
        page = requests.get(current_search)

        # Isolate the relevant data
        detail = Strainer('table', {'class': 'table2'})
        soup = Soup(page.content.decode('ISO-8859-1'), features="html.parser", parse_only=detail)

        # Extract raw html
        divs = soup.find_all("div", attrs={"class": "tt-name"})
        age_size_td = soup.find_all("td", attrs={"class": "tdnormal"})
        leech_td = soup.find_all("td", attrs={"class": "tdleech"})
        seed_td = soup.find_all("td", attrs={"class": "tdseed"})

        # Non result; early exit
        if not len(divs) > 0:
            return 1, None

        # Extract text from html
        titles = [str(div.get_text()).strip() for div in divs]
        age_size = [str(td.get_text()).strip() for td in age_size_td]
        leeches_raw = [str(td.get_text()).strip() for td in leech_td]
        seeds_raw = [str(td.get_text()).strip() for td in seed_td]

        # Filter non integer data
        leeches = []
        for leech_raw in leeches_raw:
            if leech_raw.isdigit():
                leech = leech_raw
            else:
                leech = 0
            leeches.append(leech)

        # Filter non integer data
        seeds = []
        for seed_raw in seeds_raw:
            if seed_raw.isdigit():
                seed = seed_raw
            else:
                seed = 0
            seeds.append(seed)

        # Extract links
        link_tags = [div.a for div in divs]
        links = [link['href'] for link in link_tags]

        # Post-process age_size: Parse alternating pairs of age and size into separate lists: ages and sizes
        raw_ages, raw_sizes = [], []

        for ndx in range(len(age_size)):
            if (ndx % 2) == 0:
                raw_ages.append(age_size[ndx])
            else:
                raw_sizes.append(age_size[ndx])

        # Scrub age text
        ages = []
        for raw_age in raw_ages:
            age_trim = re.sub('\s[-]\s.*$', '', raw_age)
            ages.append(age_trim)

        # Normalize size info
        sizes = []
        for raw_size in raw_sizes:
            file_size = raw_size
            file_size = file_size.replace('GB', 'G')
            file_size = file_size.replace('MB', 'M')
            file_size = file_size.replace('KB', 'K')
            sizes.append(file_size)

        # Return listStore data and provide an extra payload of link data
        torrent_list = []
        for ndx in range(0, len(titles)):
            torrent_list.append(
                (titles[ndx],
                 ages[ndx],
                 seeds[ndx],
                 leeches[ndx],
                 sizes[ndx],
                 links[ndx]))

        return 0, torrent_list


LimeModel.get_list = staticmethod(LimeModel.get_list)


class PbModel:
    myUrl = "http://thepiratebay.rocks"

    def get_list(search_phrase):
        # Prep the url
        current_search = PbModel.myUrl + '/search/' + search_phrase.replace(' ', '%20') + '/1/99/0'

        # Pull the page
        page = requests.get(current_search)

        # Extract SearchResult table
        detail = Strainer('table', {'id': 'searchResult'})
        soup = Soup(page.content.decode('ISO-8859-1'), features="html.parser", parse_only=detail)

        # Gather the sections containing pertinent info
        divs = soup.find_all("div", attrs={"class": "detName"})
        links = soup.find_all("a", attrs={"title": re.compile('^Download')})
        tds = soup.find_all("td", attrs={"align": "right"})
        size_info = soup.find_all("font", attrs={"class": "detDesc"})

        # Non result; early exit
        if not len(divs) > 0:
            return 1, None

        # Separate info into lists
        titles = [str(div.get_text()).strip() for div in divs]
        magnets = [link['href'] for link in links]
        seed_leech = [str(td.get_text()).strip()
                      for td in tds]  # will post-process
        raw_sizes = [str(info.get_text()).strip()
                     for info in size_info]  # will post-process

        # Post-process lists: Extract embedded size info from raw text
        sizes = []
        dates = []
        for raw_size in raw_sizes:
            get_date = re.search('(^.*Uploaded )(.*), Size', raw_size)
            get_sz = re.search('(^.*Size )(.*),.*$', raw_size)
            upload_date = get_date.group(2)
            upload_date = upload_date.replace(u'\xa0', ' ')
            file_size = get_sz.group(2)
            file_size = file_size.replace(u'\xa0', ' ')
            file_size = file_size.replace('GiB', 'G')
            file_size = file_size.replace('MiB', 'M')
            upload_date = re.sub(' \d{2}:\d{2}', '-' + str(datetime.now().year), upload_date)
            upload_date = re.sub(' (\d{4})', r"-\1", upload_date)
            upload_date = re.sub('(\d{2})-(\d{2})-(\d{4})', r"\3-\1-\2", upload_date)
            sizes.append(file_size)
            dates.append(upload_date)

        # Post-process lists: Parse alternating pairs of seed_leech info into separate lists: seeds and leeches
        seeds, leeches = [], []

        for sl in range(len(seed_leech)):
            if (sl % 2) == 0:
                seeds.append(seed_leech[sl])
            else:
                leeches.append(seed_leech[sl])

        # Return listStore data and provide an extra payload of magnet data
        torrent_list = []
        for ndx in range(0, len(titles)):
            torrent_list.append(
                (titles[ndx],
                 dates[ndx],
                 seeds[ndx],
                 leeches[ndx],
                 sizes[ndx],
                 magnets[ndx]))

        return 0, torrent_list


PbModel.get_list = staticmethod(PbModel.get_list)


class TorrentRequest:
    def __init__(self, engine_key=None, search_term=None):
        self.engine_key = engine_key
        self.search_term = search_term
        self.active_search = None
        self.auto_query = False if self.search_term is None else True

        search_win = SearchWin(self.engine_key, self.search_term)
        listing_win = None

        if self.auto_query is True:
            self.search_term = None  # only auto_query once

        while True:
            if search_win.torrent_list:
                self.active_search = search_win.active_search
                listing_win = ListingWin(search_win.torrent_list, self.engine_key)

            if listing_win is not None:
                if listing_win.new_search is True:
                    listing_win.destroy()
                    search_win = SearchWin(self.engine_key, self.search_term)
                    self.engine_key = search_win.engine_key

                if listing_win.new_engine is True:
                    self.engine_key = listing_win.popup_entry
                    self.search_term = None
                    listing_win.destroy()
                    search_win = SearchWin(self.engine_key, self.search_term, self.active_search)
                    self.engine_key = search_win.engine_key

                if listing_win.download is True:
                    # Pass selected magnets to torrent client and exit
                    for selected_title in listing_win.selected_titles:
                        subprocess.Popen([TORRENT_CLIENT, listing_win.magnet_dict[selected_title]],
                                         stdout=subprocess.DEVNULL,
                                         stderr=subprocess.DEVNULL)
                    sys.exit(0)


# Execute
if __name__ == "__main__":
    logger = init_logging()
    sys.excepthook = handle_exception  # uncaught exceptions to syslog

    if not os.path.exists(TORRENT_CLIENT):
        t_client = str.title(os.path.basename(TORRENT_CLIENT))
        app = os.path.basename(__file__)
        app = os.path.splitext(app)[0]
        print(
            f"{BOLD}{RED}Error{RESET}:{WHITE}{t_client} {RED}{ITALIC}not found{RESET}. Please install: {WHITE}{TORRENT_CLIENT}{RESET}")
        sys.exit(1)

    option_dict, search_term = get_cmdline()

    if len(search_term):
        search_term = ' '.join(search_term)
    else:
        search_term = None

    engineKey = option_dict["engine"]

    if engineKey not in SUPPORTED_ENGINES:
        print(f"{BOLD}{RED}Error{RESET}: engine {engineKey} is not a supported engine")
        sys.exit(1)

    TorrentRequest(engineKey, search_term)
