﻿using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Fabric.Authorization.API.Models;
using Fabric.Authorization.Domain.Exceptions;
using Fabric.Authorization.Domain.Groups;
using Nancy;
using Nancy.ModelBinding;

namespace Fabric.Authorization.API.Modules
{
    public class GroupsModule : NancyModule
    {
        public GroupsModule(IGroupService groupService) : base("/groups")
        {
            Get("/{groupName}/roles", parameters =>
            {
                try
                {
                    var groupInfoRequest = this.Bind<GroupInfoRequest>();
                    var roles = groupService.GetRolesForGroup(groupInfoRequest.GroupName, groupInfoRequest.Grain,
                        groupInfoRequest.Resource);
                    return new GroupRoleApiModel
                    {
                        RequestedGrain = groupInfoRequest.Grain,
                        RequestedResource = groupInfoRequest.Resource,
                        GroupName = groupInfoRequest.GroupName,
                        Roles = roles.Select(r => r.ToRoleApiModel())
                    };
                }
                catch (GroupNotFoundException)
                {
                    return HttpStatusCode.NotFound;
                }
                
            });

            Post("/{groupName}/roles", parameters =>
            {
                try
                {
                    var roleApiModel = this.Bind<RoleApiModel>();
                    if (roleApiModel.Id == null) throw new RoleNotFoundException();
                    groupService.AddRoleToGroup(parameters.groupName, roleApiModel.Id.Value);
                    return HttpStatusCode.NoContent;
                }
                catch (GroupNotFoundException)
                {
                    return HttpStatusCode.NotFound;
                }
                catch (RoleNotFoundException)
                {
                    return HttpStatusCode.BadRequest;
                }
            });

            Delete("/{groupName}/roles", parameters =>
            {
                try
                {
                    var roleApiModel = this.Bind<RoleApiModel>();
                    if (roleApiModel.Id == null) throw new RoleNotFoundException();
                    groupService.DeleteRoleFromGroup(parameters.groupName, roleApiModel.Id.Value);
                    return HttpStatusCode.NoContent;
                }
                catch (GroupNotFoundException)
                {
                    return HttpStatusCode.NotFound;
                }
                catch (RoleNotFoundException)
                {
                    return HttpStatusCode.BadRequest;
                }
            });
        }
    }
}
