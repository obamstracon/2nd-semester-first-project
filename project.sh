#! /Bin/bash


# Default username and password
default_username="assignment"
default_password="pass1974"

# Function to display script usage
usage() {
    echo "Usage: $0 [-u <username>] [-p <password>]"
    echo "Options:"
    echo "  -u <username>  Specify the username for creating the VMs (default: $default_username)"
    echo "  -p <password>  Specify the password for creating the VMs (default: $default_password)"
    exit 1
}

# Parse command-line arguments
while getopts "u:p:" opt; do
    case $opt in
        u)
            username="$OPTARG"
            ;;
        p)
            password="$OPTARG"
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            usage
            ;;
    esac
done

# Use default username and password if not provided
username="${username:-$default_username}"
password="${password:-$default_password}"

# Define VM names
master_vm="master"
slave_vm="slave"

# Define VM configurations
vm_memory="512"
vm_box="ubuntu/focal64"

# Create a Vagrantfile for both 'Master' and 'Slave' VMs
cat <<EOL > Vagrantfile
Vagrant.configure("2") do |config|
  config.vm.define "$master_vm" do |$master_vm|
    $master_vm.vm.box = "$vm_box"
    $master_vm.vm.network "private_network", type: "dhcp"
    $master_vm.vm.provider "virtualbox" do |vb|
      vb.memory = "$vm_memory"
      vb.cpus = 1
    end
  end

  config.vm.define "$slave_vm" do |$slave_vm|
    $slave_vm.vm.box = "$vm_box"
    $slave_vm.vm.network "private_network", type: "dhcp"
    $slave_vm.vm.provider "virtualbox" do |vb|
      vb.memory = "$vm_memory"
      vb.cpus = 1
    end
  end
end
EOL

# Create 'Master' and 'Slave' VMs
echo "Creating and provisioning '$master_vm' and '$slave_vm' VMs..."
vagrant up

# Check if both VMs are up and running else exit....
if [ "$(vagrant status | grep -c 'running')" -ne 2 ]; then
    echo "Error: Not all VMs are running. Exiting...."
    echo "Error may be due to dhcp clash or Host's BIOS vtx settings"
    exit 1
fi

# Provision 'Master' and 'Slave' nodes
echo "Provisioning '$master_vm' node with username: $username, password: xxxxxx..."
vagrant ssh $master_vm -c "sudo useradd -m $username"
vagrant ssh $master_vm -c "echo '$username ALL=(ALL) NOPASSWD: ALL' | sudo tee /etc/sudoers.d/$username"
vagrant ssh $master_vm -c "echo \"$username:$password\" | sudo chpasswd"
vagrant ssh $master_vm -c "sudo usermod -aG sudo $username"
vagrant ssh $master_vm -c "sudo su - $username -c 'mkdir -p ~/.ssh'"
vagrant ssh $master_vm -c "sudo su - $username -c 'touch ~/.ssh/authorized_keys'"
vagrant ssh $master_vm -c "sudo su - $username -c 'touch ~/.ssh/id_rsa'"
vagrant ssh $master_vm -c "sudo su - $username -c 'chmod 400 ~/.ssh/id_rsa'"
vagrant ssh $master_vm -c "sudo su - $username -c 'touch ~/.ssh/id_rsa.pub'"
createSSH="yes | sudo ssh-keygen -t rsa -N '' -f /home/$username/.ssh/id_rsa"
vagrant ssh $master_vm -c "sudo su - $username -c $createSSH"
vagrant ssh $master_vm -c "sudo su - $username -c 'cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys'"

echo "Provisioning '$slave_vm' node with username: $username, password: xxxxxx..."
vagrant ssh $slave_vm -c "sudo useradd -m $username"
vagrant ssh $slave_vm -c "sudo chmod 777 /mnt"
vagrant ssh $slave_vm -c "echo '$username ALL=(ALL) NOPASSWD: ALL' | sudo tee /etc/sudoers.d/$username"
vagrant ssh $slave_vm -c "echo \"$username:$password\" | sudo chpasswd"
vagrant ssh $slave_vm -c "sudo usermod -aG sudo $username"
vagrant ssh $slave_vm -c "sudo su - $username -c 'mkdir -p ~/.ssh'"
vagrant ssh $slave_vm -c "sudo su - $username -c 'chmod 700 ~/.ssh'"
vagrant ssh $slave_vm -c "sudo su - $username -c 'touch ~/.ssh/authorized_keys'"
vagrant ssh $slave_vm -c "sudo su - $username -c 'chmod 600 ~/.ssh/authorized_keys'"


# Copy Master's public key to Slave
echo "copying $master_vm public key to $slave_vm"
master_public_key=$(vagrant ssh $master_vm -c "sudo su - $username -c 'cat ~/.ssh/id_rsa.pub'")
vagrant ssh $slave_vm -c "sudo su - $username -c 'sudo echo $master_public_key > ~/.ssh/authorized_keys'"
# vagrant ssh $slave_vm -c "sudo su - $username -c \"sudo echo $master_public_key > ~/.ssh/authorized_keys\""

echo "SSH key-based authentication configured."

# Get the IP address of the 'Slave' VM
slave_ip_addr=$(vagrant ssh $slave_vm -c "hostname -I | awk '{print \$2}'" | tr -d '\r')

# Copy /mnt/altschool contents from Master to Slave using scp
echo "Copying contents from /mnt/altschool on '$master_vm' to /mnt/altschool/slave on '$slave_vm'..."
vagrant ssh $master_vm -c "sudo su - altschool -c 'yes | scp -o StrictHostKeyChecking=no -r /mnt/altschool/ $username@$slave_ip_addr:/mnt/altschool/slave/'"

# Display overview of Linux process management on 'Master'
echo "Overview of Linux process management on '$master_vm':"
vagrant ssh $master_vm -c "ps aux"

# Install LAMP stack on both nodes
echo "Installing LAMP stack on both nodes..."
vagrant ssh $master_vm -c "sudo apt-get update"
vagrant ssh $master_vm -c "sudo debconf-set-selections <<< 'mysql-server mysql-server/root_password password $password'"
vagrant ssh $master_vm -c "sudo debconf-set-selections <<< 'mysql-server mysql-server/root_password_again password $password'"
vagrant ssh $master_vm -c "sudo apt-get install -y apache2 mysql-server php libapache2-mod-php php-mysql"
vagrant ssh $master_vm -c "sudo systemctl enable apache2"

vagrant ssh $slave_vm -c "sudo apt-get update"
vagrant ssh $slave_vm -c "sudo debconf-set-selections <<< 'mysql-server mysql-server/root_password password $password'"
vagrant ssh $slave_vm -c "sudo debconf-set-selections <<< 'mysql-server mysql-server/root_password_again password $password'"
vagrant ssh $slave_vm -c "sudo apt-get install -y apache2 mysql-server php libapache2-mod-php php-mysql"
vagrant ssh $slave_vm -c "sudo systemctl enable apache2"

echo "LAMP stack installed and configured on both nodes."

# Validate PHP functionality with Apache
echo "Testing PHP functionality with Apache on both nodes..."

# Create a PHP test file
php_test_file="<?php phpinfo(); ?>"

vagrant ssh $master_vm -c "echo '$php_test_file' > test-$master_vm.php"
vagrant ssh $master_vm -c "sudo mv test-$master_vm.php /var/www/html/"

vagrant ssh $slave_vm -c "echo '$php_test_file' > test-$slave_vm.php"
vagrant ssh $slave_vm -c "sudo mv test-$slave_vm.php /var/www/html/"

echo "PHP test file moved to /var/www/html/"

# Get IP addresses of testing php on 'Master' and 'Slave' VMs
master_ip_list=$(vagrant ssh $master_vm -c "hostname -I")
slave_ip_list=$(vagrant ssh $slave_vm -c "hostname -I")

master_ip=$(echo "$master_ip_list" | awk '{print $2}')
slave_ip=$(echo "$slave_ip_list" | awk '{print $2}')

echo "Deployment completed!"
echo "Visit: http://$master_ip/test-$master_vm.php to validate the '$master_vm' PHP setup"
echo "Visit: http://$slave_ip/test-$slave_vm.php to validate the '$slave_vm' PHP setup"
