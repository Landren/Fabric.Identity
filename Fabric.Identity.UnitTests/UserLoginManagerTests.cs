﻿using System.Collections.Generic;
using System.Linq;
using System.Security.Claims;
using System.Threading;
using System.Threading.Tasks;
using Fabric.Identity.API.DocumentDbStores;
using Fabric.Identity.API.Management;
using Fabric.Identity.API.Services;
using Fabric.Identity.UnitTests.ClassFixtures;
using IdentityModel;
using Moq;
using Serilog;
using Xunit;

namespace Fabric.Identity.UnitTests
{
    public class UserLoginManagerTests
    {
        [Fact]
        public async Task UserLoginManager_UserLogin_NewUser_HasCorrectPropertiesSet()
        {
            //create a new user, ensure claims,  login date, provider, and name properties are set correctly
            var userLoginManager = new UserLoginManager(
                new DocumentDbUserStore(new InMemoryDocumentService(), new Mock<ILogger>().Object),
                new Mock<ILogger>().Object);

            var userId = "HealthCatalyst\\foo.bar";
            var provider = "Windows";
            var clientId = "sampleApp";
            var userName = "foo bar";
            var firstName = "foo";
            var lastName = "bar";
            var middleName = "dot";
            var claims = new List<Claim>
            {
                new Claim(ClaimTypes.Name, userName),
                new Claim(JwtClaimTypes.GivenName, firstName),
                new Claim(JwtClaimTypes.FamilyName, lastName),
                new Claim(JwtClaimTypes.MiddleName, middleName),
                new Claim(JwtClaimTypes.Role, @"FABRIC\Health Catalyst Viewer")
            };

            var newUser = await userLoginManager.UserLogin(provider, userId, claims, clientId);

            Assert.Equal(userId, newUser.SubjectId);
            Assert.Equal(provider, newUser.ProviderName);
            Assert.Equal(userName, newUser.Username);
            Assert.Equal(firstName, newUser.FirstName);
            Assert.Equal(lastName, newUser.LastName);
            Assert.Equal(middleName, newUser.MiddleName);
            Assert.Equal(5, newUser.Claims.Count);
            Assert.Equal(1, newUser.Claims.Count(c => c.Type == JwtClaimTypes.Name));
            Assert.Equal(1, newUser.Claims.Count(c => c.Type == JwtClaimTypes.Role));
            Assert.Equal(1, newUser.LastLoginDatesByClient.Count);
            Assert.Equal(clientId, newUser.LastLoginDatesByClient.First().Key);
        }

        [Fact]
        public async Task UserLoginManager_UserLogin_ExistingUser_HasPropertiesAndRoleClaimsUpdated()
        {
            var documentDbUserStore = new DocumentDbUserStore(new InMemoryDocumentService(), new Mock<ILogger>().Object);

            var userLoginManager = new UserLoginManager(documentDbUserStore, new Mock<ILogger>().Object);

            var userId = "HealthCatalyst\\foo.bar";
            var provider = "Windows";
            var clientId = "sampleApp";
            var userName = "foo bar";
            var firstName = "foo";
            var lastName = "bar";
            var middleName = "dot";
            var claims = new List<Claim>
            {
                new Claim(ClaimTypes.Name, userName),
                new Claim(JwtClaimTypes.GivenName, firstName),
                new Claim(JwtClaimTypes.FamilyName, lastName),
                new Claim(JwtClaimTypes.MiddleName, middleName),
                new Claim(JwtClaimTypes.Role, @"FABRIC\Health Catalyst Viewer")
            };

            var existingUser = await userLoginManager.UserLogin(provider, userId, claims, clientId);

            var existingRoleClaim = existingUser.Claims.Single(c => c.Type == JwtClaimTypes.Role);
            var firstLoginDate = existingUser.LastLoginDatesByClient.First().Value;

            userId = "HealthCatalyst\\foo.bar";
            provider = "Windows";
            clientId = "sampleApp";
            userName = "abc def";
            firstName = "abc";
            lastName = "def";
            middleName = "zzz";
            claims = new List<Claim>
            {
                new Claim(ClaimTypes.Name, userName),
                new Claim(JwtClaimTypes.GivenName, firstName),
                new Claim(JwtClaimTypes.FamilyName, lastName),
                new Claim(JwtClaimTypes.MiddleName, middleName),
                new Claim(JwtClaimTypes.Role, @"FABRIC\Health Catalyst Editor")
            };
                        
            var updatedUser = await userLoginManager.UserLogin(provider, userId, claims, clientId);

            Assert.Equal(userName, updatedUser.Username);
            Assert.Equal(firstName, updatedUser.FirstName);
            Assert.Equal(lastName, updatedUser.LastName);
            Assert.Equal(middleName, updatedUser.MiddleName);
            Assert.Equal(5, updatedUser.Claims.Count);
            Assert.NotEqual(existingRoleClaim.Value, updatedUser.Claims.First().Value);
            Assert.True(firstLoginDate.Ticks < updatedUser.LastLoginDatesByClient.First().Value.Ticks);
        }
    }
}
