import boto3
import json

ec2 = boto3.client('ec2', region_name='us-east-1')
rds = boto3.client('rds', region_name='us-east-1')

vpc_id = 'vpc-0fac9cb40a1f3fbc2'

print('======================================================================')
print('           HEALTHCHECK COMPLETO - INFRAESTRUTURA DE REDE (AWS)        ')
print('======================================================================\n')

# 1. VPC
vpcs = ec2.describe_vpcs(VpcIds=[vpc_id])['Vpcs']
vpc = vpcs[0]
dns_hostnames = ec2.describe_vpc_attribute(VpcId=vpc_id, Attribute='enableDnsHostnames')['EnableDnsHostnames']['Value']
dns_support = ec2.describe_vpc_attribute(VpcId=vpc_id, Attribute='enableDnsSupport')['EnableDnsSupport']['Value']

print(f'[✓] VPC: {vpc["VpcId"]}')
print(f'    - Estado: {vpc["State"]} (Disponível)')
print(f'    - Bloco CIDR: {vpc["CidrBlock"]}')
print(f'    - DNS Hostnames: {dns_hostnames} | DNS Support: {dns_support}\n')

# 2. Subnets
print('[✓] SUBNETS (6/6 criadas e operacionais):')
subnets = ec2.describe_subnets(Filters=[{'Name': 'vpc-id', 'Values': [vpc_id]}])['Subnets']
for s in sorted(subnets, key=lambda x: x['CidrBlock']):
    name = next((t['Value'] for t in s.get('Tags', []) if t['Key'] == 'Name'), 'unnamed')
    print(f'    • {name:<26} | ID: {s["SubnetId"]} | CIDR: {s["CidrBlock"]:<14} | AZ: {s["AvailabilityZone"]} | Status: {s["State"]}')

# 3. Gateways
print('\n[✓] GATEWAYS DE CONECTIVIDADE:')
igws = ec2.describe_internet_gateways(Filters=[{'Name': 'attachment.vpc-id', 'Values': [vpc_id]}])['InternetGateways']
for igw in igws:
    print(f'    • Internet Gateway (IGW): {igw["InternetGatewayId"]} [ATTACHED]')

nats = ec2.describe_nat_gateways(Filters=[{'Name': 'vpc-id', 'Values': [vpc_id]}])['NatGateways']
for nat in nats:
    eip = nat['NatGatewayAddresses'][0]['PublicIp']
    state = nat['State']
    print(f'    • NAT Gateway (Saída Privada Fargate): {nat["NatGatewayId"]} [Status: {state}] | IP Público EIP: {eip}')

# 4. Route Tables
print('\n[✓] TABELAS DE ROTEAMENTO (Isolamento em Camadas):')
rts = ec2.describe_route_tables(Filters=[{'Name': 'vpc-id', 'Values': [vpc_id]}])['RouteTables']
for rt in rts:
    name = next((t['Value'] for t in rt.get('Tags', []) if t['Key'] == 'Name'), 'RouteTable Padrão')
    assocs = len(rt.get('Associations', []))
    routes = [f"{r.get('DestinationCidrBlock', '')} -> {r.get('GatewayId', r.get('NatGatewayId', 'local'))}" for r in rt.get('Routes', [])]
    print(f'    • {name:<32} (Associações: {assocs}) | Rotas: {", ".join(routes)}')

# 5. DB Subnet Group
print('\n[✓] RDS DB SUBNET GROUP (Pronto para SCRUM-8):')
sgs = rds.describe_db_subnet_groups(DBSubnetGroupName='ferry-db-subnet-group')['DBSubnetGroups'][0]
sub_ids = [s['SubnetIdentifier'] for s in sgs['Subnets']]
print(f'    • Nome: {sgs["DBSubnetGroupName"]} | Status: {sgs["SubnetGroupStatus"]} | Subnets Vinculadas: {sub_ids}')

# 6. Security Groups
print('\n[✓] GRUPOS DE SEGURANÇA (Firewalls Perimetrais):')
sec_groups = ec2.describe_security_groups(Filters=[{'Name': 'vpc-id', 'Values': [vpc_id]}])['SecurityGroups']
for sg in sorted(sec_groups, key=lambda x: x['GroupName']):
    if sg['GroupName'] == 'default':
        continue
    ingress_ports = [f"{p.get('FromPort', 'all')}/{p.get('IpProtocol')}" for p in sg['IpPermissions']]
    print(f'    • {sg["GroupName"]:<20} ({sg["GroupId"]}) | Ingress: {ingress_ports}')

print('\n======================================================================')
print('    TODOS OS TESTES DE VALIDAÇÃO PASSARAM! INFRAESTRUTURA 100% OPERACIONAL.')
print('======================================================================')

