"""
CyberArk Password Change Automation Script

This script automates the process of changing a password for a specified user account stored within a CyberArk Safe.
It performs the following actions:
- Authenticates to CyberArk's Privileged Vault Web Access (PVWA) using Kerberos.
- Obtains a session token via LDAP authentication.
- Retrieves the account ID for the specified user.
- Initiates an immediate password change for the account.
- Waits and verifies that the password has been successfully changed.

Prerequisites:
- Python must be installed on your system.
- The 'requests' and 'requests_kerberos' Python packages must be installed:
  pip install requests
  pip install requests_kerberos
- You must have permission for using the PAS API for the account running this script.
- Ensure that the account you wish to manage has the permission to access the Safe credentials.

Configuration:
- Update the 'aim_params' dictionary with the 'AppID', 'Safe', and 'UserName' corresponding to the Safe and username you
  need to access.
- The 'username_to_find' variable in the main script should be updated with the username of the account whose password
  you want to change.

Execution:
- Run the script from the command line or an IDE:
  python script_name.py

Notes:
- The script includes a timeout mechanism that waits for the password change to propagate. If the password does not
  change after four attempts, the script will time out.
- Handle all sensitive information securely and ensure that the script is stored in a secure location with appropriate
  access controls.
- This script is compatible with both Windows and Linux environments. Ensure that Kerberos is properly configured on
  your Linux system, and the necessary Kerberos tickets are available for authentication.
"""
import requests
import json
from requests_kerberos import HTTPKerberosAuth, OPTIONAL
import time


# Global variables
pvwa_server_address = 'cyberark.example.com'
REQUEST_TIMEOUT = 10

# Function to retrieve account information using Kerberos authentication
def get_account_info_kerberos(aim_params):
    aim_url = f"https://{pvwa_server_address}/AIMWebService/api/Accounts"
    try:
        aim_response = requests.get(aim_url, params=aim_params, auth=HTTPKerberosAuth(mutual_authentication=OPTIONAL),
                                    timeout=REQUEST_TIMEOUT)
        aim_response.raise_for_status()
        return aim_response.json()
    except requests.exceptions.RequestException as e:
        print("Error retrieving account info with Kerberos:", e)
        return None


# Function to authenticate with LDAP and get a session token
def ldap_authenticate(username, password):
    ldap_url = f'https://{pvwa_server_address}/PasswordVault/API/auth/LDAP/Logon/'
    ldap_data = {'username': username, 'password': password}
    ldap_headers = {'Content-Type': 'application/json'}
    try:
        ldap_response = requests.post(ldap_url, headers=ldap_headers, data=json.dumps(ldap_data),
                                      timeout=REQUEST_TIMEOUT)
        ldap_response.raise_for_status()
        session_token = ldap_response.text.strip('"')  # Remove any surrounding quotes
        return session_token
    except requests.exceptions.RequestException as e:
        print("Error during LDAP authentication:", e)
        return None


# Function to get the account ID for a specific user
def get_account_id_for_user(session_token, username_to_find):
    url = f"https://{pvwa_server_address}/PasswordVault/API/Accounts"
    headers = {'Authorization': session_token, 'Content-Type': 'application/json'}
    try:
        response = requests.get(url, headers=headers, timeout=REQUEST_TIMEOUT)
        response.raise_for_status()
        accounts_data = response.json()
        if 'value' in accounts_data:
            for account in accounts_data['value']:
                if account['userName'] == username_to_find:
                    return account['id']
        else:
            print("Unexpected data format received")
    except requests.exceptions.RequestException as e:
        print(f"An error occurred while retrieving accounts: {e}")
    return None


# Function to change the password immediately for a specific account
def change_password(account_id, session_token):
    url = f"https://{pvwa_server_address}/PasswordVault/API/Accounts/{account_id}/Change/"
    headers = {
        'Authorization': session_token,
        'Content-Type': 'application/json'
    }
    body = {
        "ChangeEntireGroup": False  # Set to False to change password for this account only
    }

    try:
        response = requests.post(url, headers=headers, json=body, timeout=REQUEST_TIMEOUT)
        response.raise_for_status()
        print(f"Password change initiated successfully.")
    except requests.exceptions.RequestException as e:
        print(f"An error occurred while initiating password change: {e}")


# Function to check if the password has changed
def wait_for_password_change(aim_params, original_password):
    max_attempts = 5
    attempt = 0
    while attempt < max_attempts:
        account_info = get_account_info_kerberos(aim_params)
        if account_info and 'Content' in account_info:
            if account_info['Content'] != original_password:
                print("The password has successfully changed.")
                return True
            else:
                print("The password has not changed yet. Waiting for 90 seconds before retrying...")
                time.sleep(90)  # Wait for 1 minute 30 seconds
        else:
            print("Failed to retrieve account information.")
            return False
        attempt += 1

    print("Timeout reached. The password has not changed after 4 attempts.")
    return False


# Main script execution
if __name__ == "__main__":
    aim_params = {
        "AppID": "APP-ID",
        "Safe": "SAFE-NAME",
        "UserName": "account_name"
    }
    account_info = get_account_info_kerberos(aim_params)
    if account_info:
        original_password = account_info['Content']
        session_token = ldap_authenticate(account_info['UserName'], original_password)
        if session_token:
            username_to_find = 'account_name'
            account_id = get_account_id_for_user(session_token, username_to_find)
            if account_id:
                change_password(account_id, session_token)
                # Wait for the password to change
                password_changed = wait_for_password_change(aim_params, original_password)
            else:
                print(f"Account ID for user '{username_to_find}' not found or an error occurred.")
        else:
            print("LDAP Authentication Test Failed.")
    else:
        print("Kerberos Authentication Test Failed.")
