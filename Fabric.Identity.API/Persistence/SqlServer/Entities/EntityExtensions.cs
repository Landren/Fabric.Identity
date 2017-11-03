﻿using System.Linq;
using System.Security.Claims;
using Fabric.Identity.API.Models;
using IdentityServer4.EntityFramework.Entities;
using IdentityServer4.EntityFramework.Mappers;
using Microsoft.AspNetCore.Server.Kestrel.Internal.Networking;

namespace Fabric.Identity.API.Persistence.SqlServer.Entities
{
    public static class EntityExtensions
    {
        public static ClientEntity ToFabricEntity(this IdentityServer4.Models.Client is4Client)
        {
            var entityModel = is4Client.ToEntity();
            return (ClientEntity)entityModel;
        }

        public static ApiResourceEntity ToFabricEntity(this IdentityServer4.Models.ApiResource is4ApiResource)
        {
            var entityModel = is4ApiResource.ToEntity();
            return (ApiResourceEntity) entityModel;
        }

        public static IdentityResourceEntity ToFabricEntity(this IdentityServer4.Models.IdentityResource is4IdentityResource)
        {
            var entityModel = is4IdentityResource.ToEntity();
            return (IdentityResourceEntity)entityModel;
        }

        public static UserEntity ToFabricEntity(this User user)
        {
            var entityModel = new UserEntity
            {
                FirstName = user.FirstName,
                LastName = user.LastName,
                MiddleName = user.MiddleName,
                SubjectId = user.SubjectId,
                ProviderName = user.ProviderName,
                Username = user.Username
            };

            return entityModel;
        }
    }
}