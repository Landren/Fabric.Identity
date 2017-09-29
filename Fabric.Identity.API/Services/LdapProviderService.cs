﻿using System.Collections.Generic;
using System.Linq;
using Fabric.Identity.API.Configuration;
using Fabric.Identity.API.Models;
using Novell.Directory.Ldap;
using Serilog;

namespace Fabric.Identity.API.Services
{
    public class LdapProviderService : IExternalIdentityProviderService
    {
        private readonly ILdapConnectionProvider _ldapConnectionProvider;
        private readonly ILogger _logger;
        public LdapProviderService(ILdapConnectionProvider ldapConnectionProvider, ILogger logger)
        {
            _ldapConnectionProvider = ldapConnectionProvider;
            _logger = logger;
        }
        public ExternalUser FindUserBySubjectId(string subjectId)
        {
            if (!subjectId.Contains(@"\"))
            {
                _logger.Information("subjectId '{subjectId}' was not in the correct format. Expected DOMAIN\\username.");
                return new ExternalUser();
            }
            var subjectIdParts = subjectId.Split('\\');
            var accountName = subjectIdParts[subjectIdParts.Length - 1];
            var ldapQuery = $"(&(objectClass=user)(objectCategory=person)(sAMAccountName={accountName}*))";
            var users = SearchLdap(ldapQuery);
            return users.FirstOrDefault();
        }

        public ICollection<ExternalUser> SearchUsers(string searchText)
        {
            var ldapQuery = $"(&(objectClass=user)(objectCategory=person)(|(sAMAccountName={searchText}*)(givenName={searchText}*)(sn={searchText}*)))";
            return SearchLdap(ldapQuery);
        }

        private ICollection<ExternalUser> SearchLdap(string ldapQuery)
        {
            var users = new List<ExternalUser>();
            using (var ldapConnection = _ldapConnectionProvider.GetConnection())
            {
                var results = ldapConnection.Search(string.Empty, LdapConnection.SCOPE_SUB, ldapQuery, null, false);
                while (results.hasMore())
                {
                    var next = results.next();
                    var atttributes = next.getAttributeSet();
                    var user = new ExternalUser
                    {
                        LastName = atttributes.getAttribute("SN").StringValue,
                        FirstName = atttributes.getAttribute("GIVENNAME").StringValue,
                        Username = atttributes.getAttribute("SAMACCOUNTNAME").StringValue
                    };
                    users.Add(user);
                }
                return users;
            }
        }
    }
}
