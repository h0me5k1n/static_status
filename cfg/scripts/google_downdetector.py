#!/usr/bin/env python3
"""
A simple selenium test example written by python
"""

import unittest
from selenium import webdriver
from selenium.common.exceptions import NoSuchElementException
from selenium.webdriver.common.keys import Keys
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.common.by import By
from selenium.webdriver.chrome.options import Options
import time

#  variables
webserv="https://downdetector.com/status/google/"
vService='Google' # enter the keyword for test 
keyword='User reports indicate no current problems at ' + vService # enter the keyword for test 
TIMEOUT=3

class TestTemplate(unittest.TestCase):

    def setUp(self):
        """Start web driver"""
        chrome_options = webdriver.ChromeOptions()
        chrome_options.add_argument('--no-sandbox')
        chrome_options.add_argument('--headless')
        chrome_options.add_argument('--disable-gpu')
        self.driver = webdriver.Chrome(options=chrome_options)
        self.driver.implicitly_wait(10)

    def tearDown(self):
        """Stop web driver"""
        self.driver.quit()

    def test_case_1(self):
        # functions
        wait = WebDriverWait(self.driver, TIMEOUT)
        
        try:
            
            print("Opening " + webserv)
            self.driver.get(webserv)
            print("Checking for visibility of \"" + keyword + "\" on downdetector page for " + vService)
            wait.until(EC.visibility_of_element_located((By.XPATH, "//*[contains(text(),'" + keyword + "')]")))
            print("Completed successfully")

        except NoSuchElementException as ex:
            print("Error occurred")
            self.fail(ex.msg)

if __name__ == '__main__':
    suite = unittest.TestLoader().loadTestsFromTestCase(TestTemplate)
    unittest.TextTestRunner(verbosity=2).run(suite)